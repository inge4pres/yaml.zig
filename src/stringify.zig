const std = @import("std");
const Value = @import("value.zig").Value;

/// Configuration options for YAML serialization
pub const StringifyOptions = struct {
    /// Number of spaces per indentation level (default: 2)
    indent_size: usize = 2,

    /// Use flow style for sequences when they contain only scalars and are short
    compact_sequences: bool = false,

    /// Use flow style for mappings when they are simple and short
    compact_mappings: bool = false,

    /// Maximum length for flow style collections (default: 60)
    flow_threshold: usize = 60,
};

/// Serializes a Value to YAML format
pub fn stringify(value: Value, writer: *std.Io.Writer) !void {
    return stringifyWithOptions(value, writer, .{});
}

/// Serializes a Value to YAML format with custom options
pub fn stringifyWithOptions(value: Value, writer: *std.Io.Writer, options: StringifyOptions) !void {
    var ctx = Writer{
        .writer = writer,
        .options = options,
    };
    try ctx.writeValue(value, false);
    try writer.writeAll("\n");
}

const Writer = struct {
    writer: *std.Io.Writer,
    options: StringifyOptions,
    indent_cursor: usize = 0,

    const Self = @This();

    fn writeValue(self: *Self, value: Value, inline_start: bool) anyerror!void {
        switch (value) {
            .null => try self.writer.writeAll("null"),
            .bool => |b| try self.writer.print("{}", .{b}),
            .int => |i| try self.writer.print("{d}", .{i}),
            .float => |f| {
                if (std.math.isNan(f)) {
                    try self.writer.writeAll(".nan");
                } else if (std.math.isInf(f)) {
                    if (f > 0) {
                        try self.writer.writeAll(".inf");
                    } else {
                        try self.writer.writeAll("-.inf");
                    }
                } else {
                    // Format float, ensuring we don't lose precision
                    const formatted = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{f});
                    defer std.heap.page_allocator.free(formatted);

                    // If it looks like an integer, add .0
                    if (std.mem.indexOf(u8, formatted, ".") == null and
                        std.mem.indexOf(u8, formatted, "e") == null)
                    {
                        try self.writer.writeAll(formatted);
                        try self.writer.writeAll(".0");
                    } else {
                        try self.writer.writeAll(formatted);
                    }
                }
            },
            .string => |s| try self.writeString(s),
            .sequence => |seq| try self.writeSequence(seq, inline_start),
            .mapping => |map| try self.writeMapping(map, inline_start),
        }
    }

    fn writeString(self: *Self, s: []const u8) !void {
        // Determine if the string needs quoting
        if (needsQuoting(s)) {
            // Use double quotes and escape special characters
            try self.writer.writeAll("\"");
            for (s) |c| {
                switch (c) {
                    '\n' => try self.writer.writeAll("\\n"),
                    '\r' => try self.writer.writeAll("\\r"),
                    '\t' => try self.writer.writeAll("\\t"),
                    '\\' => try self.writer.writeAll("\\\\"),
                    '"' => try self.writer.writeAll("\\\""),
                    else => {
                        if (c < 32 or c == 127) {
                            // Control character - use hex escape
                            try self.writer.print("\\x{x:0>2}", .{c});
                        } else {
                            try self.writer.writeByte(c);
                        }
                    },
                }
            }
            try self.writer.writeAll("\"");
        } else {
            try self.writer.writeAll(s);
        }
    }

    fn writeSequence(self: *Self, seq: Value.Sequence, _: bool) !void {
        if (seq.items.len == 0) {
            try self.writer.writeAll("[]");
            return;
        }

        // Check if we should use flow style
        if (self.options.compact_sequences and self.shouldUseFlowStyle(seq.items)) {
            try self.writeFlowSequence(seq);
            return;
        }

        // Block style
        for (seq.items, 0..) |item, i| {
            if (i > 0) {
                try self.writer.writeAll("\n");
                try self.writeIndent();
            }
            try self.writer.writeAll("- ");

            // For complex nested items, indent them
            const needs_nesting = switch (item) {
                .sequence, .mapping => true,
                else => false,
            };

            if (needs_nesting) {
                self.indent_cursor += 1;
                try self.writeValue(item, true);
                self.indent_cursor -= 1;
            } else {
                try self.writeValue(item, true);
            }
        }
    }

    fn writeFlowSequence(self: *Self, seq: Value.Sequence) !void {
        try self.writer.writeAll("[");
        for (seq.items, 0..) |item, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.writeValue(item, true);
        }
        try self.writer.writeAll("]");
    }

    fn writeMapping(self: *Self, map: Value.Mapping, _: bool) !void {
        if (map.count() == 0) {
            try self.writer.writeAll("{}");
            return;
        }

        // Check if we should use flow style
        if (self.options.compact_mappings and self.shouldUseFlowStyleMap(&map)) {
            try self.writeFlowMapping(map);
            return;
        }

        // Block style - collect and sort keys for deterministic output
        var keys = std.ArrayList([]const u8){};
        defer keys.deinit(std.heap.page_allocator);

        var iter = map.iterator();
        while (iter.next()) |entry| {
            try keys.append(std.heap.page_allocator, entry.key_ptr.*);
        }

        std.mem.sort([]const u8, keys.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        for (keys.items, 0..) |key, i| {
            if (i > 0) {
                try self.writer.writeAll("\n");
                try self.writeIndent();
            }

            // Write key
            try self.writeString(key);
            try self.writer.writeAll(": ");

            // Write value
            const val = map.get(key).?;
            const needs_nesting = switch (val) {
                .sequence, .mapping => true,
                else => false,
            };

            if (needs_nesting) {
                try self.writer.writeAll("\n");
                self.indent_cursor += 1;
                try self.writeIndent();
                try self.writeValue(val, true);
                self.indent_cursor -= 1;
            } else {
                try self.writeValue(val, true);
            }
        }
    }

    fn writeFlowMapping(self: *Self, map: Value.Mapping) !void {
        try self.writer.writeAll("{");

        // Collect and sort keys
        var keys = std.ArrayList([]const u8){};
        defer keys.deinit(std.heap.page_allocator);

        var iter = map.iterator();
        while (iter.next()) |entry| {
            try keys.append(std.heap.page_allocator, entry.key_ptr.*);
        }

        std.mem.sort([]const u8, keys.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        for (keys.items, 0..) |key, i| {
            if (i > 0) try self.writer.writeAll(", ");
            try self.writeString(key);
            try self.writer.writeAll(": ");
            try self.writeValue(map.get(key).?, true);
        }

        try self.writer.writeAll("}");
    }

    fn writeIndent(self: *Self) !void {
        const spaces = self.indent_cursor * self.options.indent_size;
        var space_buf: [1][]const u8 = .{&.{' '}};
        try self.writer.writeSplatAll(&space_buf, spaces);
    }

    fn shouldUseFlowStyle(self: *Self, items: []const Value) bool {
        // Only use flow style for scalar-only sequences that are reasonably short
        var estimated_length: usize = 2; // []
        for (items, 0..) |item, i| {
            if (i > 0) estimated_length += 2; // ", "

            const item_len = switch (item) {
                .null => 4,
                .bool => 5,
                .int => 10,
                .float => 15,
                .string => |s| s.len + 2, // Quotes
                else => return false, // Complex items
            };
            estimated_length += item_len;
        }
        return estimated_length <= self.options.flow_threshold;
    }

    fn shouldUseFlowStyleMap(self: *Self, map: *const Value.Mapping) bool {
        // Only use flow style for scalar-only mappings that are reasonably short
        if (map.count() > 4) return false;

        var estimated_length: usize = 2; // {}
        var iter = map.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) estimated_length += 2; // ", "
            first = false;

            estimated_length += entry.key_ptr.*.len + 2; // key + ": "

            const val_len = switch (entry.value_ptr.*) {
                .null => 4,
                .bool => 5,
                .int => 10,
                .float => 15,
                .string => |s| s.len + 2,
                else => return false, // Complex values
            };
            estimated_length += val_len;
        }
        return estimated_length <= self.options.flow_threshold;
    }
};

/// Determines if a string needs quoting in YAML
fn needsQuoting(s: []const u8) bool {
    if (s.len == 0) return true;

    // Check for reserved words that could be misinterpreted
    const reserved = [_][]const u8{ "null", "true", "false", "yes", "no", "on", "off", "~" };
    for (reserved) |word| {
        if (std.mem.eql(u8, s, word)) return true;
    }

    // Check if it looks like a number
    if (looksLikeNumber(s)) return true;

    // Check for special characters that need quoting
    const special_chars = "-?:,[]{}#&*!|>'\"%@`\n\r\t\\";

    // First character checks
    if (std.mem.indexOfScalar(u8, special_chars, s[0]) != null) return true;
    if (s[0] == ' ' or s[s.len - 1] == ' ') return true;

    // Check rest of string for problematic characters
    for (s) |c| {
        if (c < 32 or c == 127) return true; // Control characters
        if (c == ':' or c == '#') return true; // Can cause parsing issues
    }

    return false;
}

fn looksLikeNumber(s: []const u8) bool {
    if (s.len == 0) return false;

    // Check for special float values
    if (std.mem.eql(u8, s, ".inf") or std.mem.eql(u8, s, "-.inf") or
        std.mem.eql(u8, s, ".nan") or std.mem.eql(u8, s, ".Inf") or
        std.mem.eql(u8, s, "-.Inf") or std.mem.eql(u8, s, ".NaN"))
    {
        return true;
    }

    // Simple heuristic: starts with digit or +/- followed by digit
    if (s[0] >= '0' and s[0] <= '9') return true;
    if (s.len > 1 and (s[0] == '+' or s[0] == '-') and s[1] >= '0' and s[1] <= '9') return true;
    if (s.len > 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'o')) return true;

    return false;
}
