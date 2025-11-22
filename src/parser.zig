const std = @import("std");
const Allocator = std.mem.Allocator;
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("scanner.zig").Token;
const Value = @import("value.zig").Value;
const schema = @import("schema.zig");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEndOfStream,
    UnknownAlias,
    InvalidSyntax,
    OutOfMemory,
    InvalidBool,
    InvalidInt,
    InvalidFloat,
    InvalidTag,
};

pub const Parsed = struct {
    value: Value,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: *Parsed) void {
        const allocator = self.arena.child_allocator;
        self.value.deinit(self.arena.allocator());
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};

pub const Parser = struct {
    scanner: Scanner,
    allocator: Allocator,
    anchors: std.StringHashMap(Value),
    current_tag: ?[]const u8,
    peeked_token: ?Token,
    in_flow_context: bool,

    pub fn init(allocator: Allocator, input: []const u8) !Parser {
        return Parser{
            .scanner = try Scanner.init(allocator, input),
            .allocator = allocator,
            .anchors = std.StringHashMap(Value).init(allocator),
            .current_tag = null,
            .peeked_token = null,
            .in_flow_context = false,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.scanner.deinit();
        self.anchors.deinit();
    }

    fn nextToken(self: *Parser) !?Token {
        if (self.peeked_token) |token| {
            self.peeked_token = null;
            return token;
        }
        return try self.scanner.next();
    }

    fn peekToken(self: *Parser) !?Token {
        if (self.peeked_token == null) {
            self.peeked_token = try self.scanner.next();
        }
        return self.peeked_token;
    }

    pub fn parseDocument(self: *Parser) !Value {
        // Skip document start marker if present
        var token = try self.nextToken();
        if (token) |t| {
            if (t == .document_start) {
                token = try self.nextToken();
            }
        }

        if (token == null or token.? == .stream_end) {
            return .{ .null = {} };
        }

        return try self.parseValue(token.?);
    }

    fn parseValue(self: *Parser, token: Token) ParseError!Value {
        return switch (token) {
            .scalar => |s| {
                if (self.in_flow_context) {
                    return try self.parseScalar(s);
                } else {
                    return try self.parseBlockMappingFromScalar(s);
                }
            },
            .alias => |a| try self.resolveAlias(a),
            .anchor => |a| try self.parseAnchoredNode(a),
            .tag => |t| try self.parseTaggedNode(t),
            .block_entry => try self.parseBlockSequence(),
            .flow_sequence_start => try self.parseFlowSequence(),
            .flow_mapping_start => try self.parseFlowMapping(),
            .key => try self.parseBlockMapping(),
            else => return ParseError.UnexpectedToken,
        };
    }

    fn parseScalar(self: *Parser, scalar: Token.Scalar) !Value {
        const val = try schema.resolveScalar(self.allocator, scalar.value, self.current_tag);
        self.current_tag = null;
        return val;
    }

    fn parseBlockSequence(self: *Parser) !Value {
        var val = Value.initSequence(self.allocator);
        var seq = val.asSequence().?;

        while (true) {
            // We already saw a block_entry token
            var item_token = try self.nextToken();

            if (item_token == null or item_token.? == .stream_end) {
                break;
            }

            if (item_token.? == .block_entry) {
                // Nested entry, get the actual value
                item_token = try self.nextToken();
                if (item_token == null) break;
            }

            const item = try self.parseValue(item_token.?);
            try seq.append(self.allocator, item);

            // Check if there's another entry
            const peek = try self.peekToken();
            if (peek == null or peek.? != .block_entry) {
                // No more entries, we're done
                break;
            }
            // Continue loop - next iteration will consume the block_entry
        }

        return val;
    }

    fn parseFlowSequence(self: *Parser) !Value {
        const was_in_flow = self.in_flow_context;
        self.in_flow_context = true;
        defer self.in_flow_context = was_in_flow;

        var val = Value.initSequence(self.allocator);
        var seq = val.asSequence().?;

        while (true) {
            const token = try self.nextToken();

            if (token == null or token.? == .stream_end) {
                return ParseError.UnexpectedEndOfStream;
            }

            if (token.? == .flow_sequence_end) {
                break;
            }

            if (token.? == .flow_entry) {
                continue; // Skip commas
            }

            const item = try self.parseValue(token.?);
            try seq.append(self.allocator, item);
        }

        return val;
    }

    fn parseBlockMapping(self: *Parser) !Value {
        var val = Value.initMapping(self.allocator);
        var map = val.asMapping().?;

        while (true) {
            // We saw a key indicator, get the key
            const key_token = try self.nextToken();
            if (key_token == null or key_token.? == .stream_end) {
                break;
            }

            // Get the key
            const key_val = try self.parseValue(key_token.?);
            const key_str = if (key_val.asString()) |s|
                try self.allocator.dupe(u8, s)
            else
                return ParseError.InvalidSyntax;

            // Expect value indicator
            const value_indicator = try self.nextToken();
            if (value_indicator == null or value_indicator.? != .value) {
                return ParseError.UnexpectedToken;
            }

            // Get the value
            const val_token = try self.nextToken();
            if (val_token == null) {
                return ParseError.UnexpectedEndOfStream;
            }

            const value_val = try self.parseValue(val_token.?);
            try map.put(key_str, value_val);

            // Check for another key
            const peek = try self.nextToken();
            if (peek == null or peek.? != .key) {
                break;
            }
        }

        return val;
    }

    fn parseBlockMappingFromScalar(self: *Parser, first_key: Token.Scalar) !Value {
        var val = Value.initMapping(self.allocator);
        var map = val.asMapping().?;

        // First key-value pair
        const first_key_str = try self.allocator.dupe(u8, first_key.value);

        const value_indicator = try self.nextToken();
        if (value_indicator == null or value_indicator.? != .value) {
            // Not a mapping, push back the token and return the scalar
            self.peeked_token = value_indicator;
            self.allocator.free(first_key_str);
            val.deinit(self.allocator);
            return try self.parseScalar(first_key);
        }

        const first_val_token = try self.nextToken();
        if (first_val_token == null) {
            return ParseError.UnexpectedEndOfStream;
        }

        const first_value = try self.parseValue(first_val_token.?);
        try map.put(first_key_str, first_value);

        // Continue parsing remaining pairs
        while (true) {
            const key_token = try self.nextToken();
            if (key_token == null or key_token.? == .stream_end or key_token.? == .document_end) {
                break;
            }

            if (key_token.? != .scalar) {
                // End of mapping, push back this token
                self.peeked_token = key_token;
                break;
            }

            const key_str = try self.allocator.dupe(u8, key_token.?.scalar.value);

            // Check for value indicator
            const val_indicator = try self.nextToken();
            if (val_indicator == null or val_indicator.? != .value) {
                self.allocator.free(key_str);
                self.peeked_token = val_indicator;
                break;
            }

            const val_token = try self.nextToken();
            if (val_token == null) {
                self.allocator.free(key_str);
                break;
            }

            const value_val = try self.parseValue(val_token.?);
            try map.put(key_str, value_val);
        }

        return val;
    }

    fn parseFlowMapping(self: *Parser) !Value {
        const was_in_flow = self.in_flow_context;
        self.in_flow_context = true;
        defer self.in_flow_context = was_in_flow;

        var val = Value.initMapping(self.allocator);
        var map = val.asMapping().?;

        while (true) {
            const key_token = try self.nextToken();

            if (key_token == null or key_token.? == .stream_end) {
                return ParseError.UnexpectedEndOfStream;
            }

            if (key_token.? == .flow_mapping_end) {
                break;
            }

            if (key_token.? == .flow_entry) {
                continue; // Skip commas
            }

            // Get the key
            const key_val = try self.parseValue(key_token.?);
            const key_str = if (key_val.asString()) |s|
                try self.allocator.dupe(u8, s)
            else
                return ParseError.InvalidSyntax;

            // Expect value indicator
            const value_indicator = try self.nextToken();
            if (value_indicator == null or value_indicator.? != .value) {
                return ParseError.UnexpectedToken;
            }

            // Get the value
            const val_token = try self.nextToken();
            if (val_token == null) {
                return ParseError.UnexpectedEndOfStream;
            }

            const value_val = try self.parseValue(val_token.?);
            try map.put(key_str, value_val);
        }

        return val;
    }

    fn parseAnchoredNode(self: *Parser, anchor: []const u8) !Value {
        const token = try self.nextToken();
        if (token == null) {
            return ParseError.UnexpectedEndOfStream;
        }

        const value = try self.parseValue(token.?);

        // Store the anchor
        const anchor_copy = try self.allocator.dupe(u8, anchor);
        try self.anchors.put(anchor_copy, value);

        return value;
    }

    fn resolveAlias(self: *Parser, alias: []const u8) !Value {
        if (self.anchors.get(alias)) |value| {
            return value;
        }
        return ParseError.UnknownAlias;
    }

    fn parseTaggedNode(self: *Parser, tag: []const u8) !Value {
        self.current_tag = tag;
        const token = try self.nextToken();
        if (token == null) {
            return ParseError.UnexpectedEndOfStream;
        }
        return try self.parseValue(token.?);
    }
};

/// High-level parse function
pub fn parseFromSlice(allocator: Allocator, input: []const u8) !Parsed {
    var arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }

    const arena_allocator = arena.allocator();

    var parser = try Parser.init(arena_allocator, input);
    defer parser.deinit();

    const value = try parser.parseDocument();

    return Parsed{
        .value = value,
        .arena = arena,
    };
}

// Tests
const testing = std.testing;

test "parse null" {
    var parsed = try parseFromSlice(testing.allocator, "null");
    defer parsed.deinit();

    try testing.expect(parsed.value.isNull());
}

test "parse boolean" {
    var parsed = try parseFromSlice(testing.allocator, "true");
    defer parsed.deinit();

    try testing.expectEqual(true, parsed.value.asBool().?);
}

test "parse integer" {
    var parsed = try parseFromSlice(testing.allocator, "42");
    defer parsed.deinit();

    try testing.expectEqual(@as(i64, 42), parsed.value.asInt().?);
}

test "parse string" {
    var parsed = try parseFromSlice(testing.allocator, "hello");
    defer parsed.deinit();

    try testing.expectEqualStrings("hello", parsed.value.asString().?);
}

test "parse simple sequence" {
    const input = "- a\n- b\n- c";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence();
    try testing.expect(seq != null);
    try testing.expectEqual(@as(usize, 3), seq.?.items.len);
}

test "parse simple mapping" {
    const input = "key1: value1\nkey2: value2";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 2), map.?.count());
}

test "parse flow sequence" {
    const input = "[1, 2, 3]";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence();
    try testing.expect(seq != null);
    try testing.expectEqual(@as(usize, 3), seq.?.items.len);
}

test "parse flow mapping" {
    const input = "{a: 1, b: 2}";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 2), map.?.count());
}
