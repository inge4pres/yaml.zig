const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = union(enum) {
    // Structural tokens
    stream_start,
    stream_end,
    document_start, // ---
    document_end, // ...
    block_sequence_start,
    block_mapping_start,
    block_end,
    flow_sequence_start, // [
    flow_sequence_end, // ]
    flow_mapping_start, // {
    flow_mapping_end, // }
    block_entry, // -
    flow_entry, // ,
    key, // ? (explicit key indicator)
    value, // :

    // Content tokens
    alias: []const u8, // *anchor_name
    anchor: []const u8, // &anchor_name
    tag: []const u8, // !!str or !local
    scalar: Scalar,

    // Meta
    comment: []const u8,
    error_token: Error,

    pub const Scalar = struct {
        value: []const u8,
        style: Style,

        pub const Style = enum {
            plain,
            single_quoted,
            double_quoted,
            literal, // |
            folded, // >
        };
    };

    pub const Error = struct {
        message: []const u8,
        line: usize,
        column: usize,
    };
};

pub const Scanner = struct {
    input: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    allocator: Allocator,
    indent_stack: std.ArrayList(usize),
    flow_level: usize,
    tokens: std.ArrayList(Token),
    done: bool,

    pub fn init(allocator: Allocator, input: []const u8) !Scanner {
        var scanner = Scanner{
            .input = input,
            .pos = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
            .indent_stack = std.ArrayList(usize){},
            .flow_level = 0,
            .tokens = std.ArrayList(Token){},
            .done = false,
        };
        try scanner.indent_stack.append(allocator, 0);
        return scanner;
    }

    pub fn deinit(self: *Scanner) void {
        self.indent_stack.deinit(self.allocator);
        self.tokens.deinit(self.allocator);
    }

    pub fn next(self: *Scanner) !?Token {
        if (self.tokens.items.len > 0) {
            return self.tokens.orderedRemove(0);
        }

        if (self.done) {
            return null;
        }

        // Skip whitespace and comments
        self.skipWhitespaceAndComments();

        if (self.pos >= self.input.len) {
            self.done = true;
            return .stream_end;
        }

        return try self.scanNext();
    }

    fn scanNext(self: *Scanner) !Token {
        const c = self.input[self.pos];

        // Flow indicators
        if (self.flow_level > 0 or c == '[' or c == '{') {
            switch (c) {
                '[' => {
                    self.advance();
                    self.flow_level += 1;
                    return .flow_sequence_start;
                },
                ']' => {
                    self.advance();
                    if (self.flow_level > 0) self.flow_level -= 1;
                    return .flow_sequence_end;
                },
                '{' => {
                    self.advance();
                    self.flow_level += 1;
                    return .flow_mapping_start;
                },
                '}' => {
                    self.advance();
                    if (self.flow_level > 0) self.flow_level -= 1;
                    return .flow_mapping_end;
                },
                ',' => {
                    self.advance();
                    return .flow_entry;
                },
                else => {},
            }
        }

        // Block indicators
        switch (c) {
            '-' => {
                if (self.pos + 2 < self.input.len and
                    self.input[self.pos + 1] == '-' and
                    self.input[self.pos + 2] == '-')
                {
                    self.pos += 3;
                    self.column += 3;
                    return .document_start;
                }
                if (self.isWhitespaceOrEnd(self.pos + 1)) {
                    self.advance();
                    return .block_entry;
                }
            },
            '.' => {
                if (self.pos + 2 < self.input.len and
                    self.input[self.pos + 1] == '.' and
                    self.input[self.pos + 2] == '.')
                {
                    self.pos += 3;
                    self.column += 3;
                    return .document_end;
                }
            },
            ':' => {
                if (self.isWhitespaceOrEnd(self.pos + 1)) {
                    self.advance();
                    return .value;
                }
            },
            '?' => {
                if (self.isWhitespaceOrEnd(self.pos + 1)) {
                    self.advance();
                    return .key;
                }
            },
            '&' => {
                self.advance();
                return .{ .anchor = try self.scanAnchorName() };
            },
            '*' => {
                self.advance();
                return .{ .alias = try self.scanAnchorName() };
            },
            '!' => {
                return .{ .tag = try self.scanTag() };
            },
            '\'' => {
                return .{ .scalar = try self.scanSingleQuoted() };
            },
            '"' => {
                return .{ .scalar = try self.scanDoubleQuoted() };
            },
            '|' => {
                if (self.isWhitespaceOrEnd(self.pos + 1)) {
                    self.advance();
                    return .{ .scalar = try self.scanLiteral() };
                }
            },
            '>' => {
                if (self.isWhitespaceOrEnd(self.pos + 1)) {
                    self.advance();
                    return .{ .scalar = try self.scanFolded() };
                }
            },
            else => {},
        }

        // Default to plain scalar
        return .{ .scalar = try self.scanPlain() };
    }

    fn scanPlain(self: *Scanner) !Token.Scalar {
        const start = self.pos;

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];

            // Stop at flow indicators in flow context
            if (self.flow_level > 0) {
                if (c == ',' or c == '[' or c == ']' or c == '{' or c == '}') {
                    break;
                }
            }

            // Stop at : followed by whitespace
            if (c == ':' and self.isWhitespaceOrEnd(self.pos + 1)) {
                break;
            }

            // Stop at newline in block context
            if (c == '\n' and self.flow_level == 0) {
                break;
            }

            // Stop at comment
            if (c == '#' and (self.pos == 0 or self.isWhitespace(self.input[self.pos - 1]))) {
                break;
            }

            self.advance();
        }

        const value = std.mem.trim(u8, self.input[start..self.pos], " \t");

        return .{
            .value = value,
            .style = .plain,
        };
    }

    fn scanSingleQuoted(self: *Scanner) !Token.Scalar {
        self.advance(); // Skip opening '
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '\'') {
                if (self.pos + 1 < self.input.len and self.input[self.pos + 1] == '\'') {
                    // Escaped quote
                    try buf.append(self.allocator, '\'');
                    self.pos += 2;
                    self.column += 2;
                } else {
                    // End of string
                    self.advance();
                    break;
                }
            } else {
                try buf.append(self.allocator, c);
                self.advance();
            }
        }

        const value = try self.allocator.dupe(u8, buf.items);
        return .{
            .value = value,
            .style = .single_quoted,
        };
    }

    fn scanDoubleQuoted(self: *Scanner) !Token.Scalar {
        self.advance(); // Skip opening "
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '"') {
                self.advance();
                break;
            } else if (c == '\\') {
                self.advance();
                if (self.pos < self.input.len) {
                    const escape_char = self.input[self.pos];
                    switch (escape_char) {
                        'n' => try buf.append(self.allocator, '\n'),
                        't' => try buf.append(self.allocator, '\t'),
                        'r' => try buf.append(self.allocator, '\r'),
                        '\\' => try buf.append(self.allocator, '\\'),
                        '"' => try buf.append(self.allocator, '"'),
                        '0' => try buf.append(self.allocator, 0),
                        // TODO: Handle \uXXXX and \UXXXXXXXX
                        else => {
                            try buf.append(self.allocator, '\\');
                            try buf.append(self.allocator, escape_char);
                        },
                    }
                    self.advance();
                }
            } else {
                try buf.append(self.allocator, c);
                self.advance();
            }
        }

        const value = try self.allocator.dupe(u8, buf.items);
        return .{
            .value = value,
            .style = .double_quoted,
        };
    }

    fn scanLiteral(self: *Scanner) !Token.Scalar {
        self.skipWhitespaceOnLine();
        if (self.pos < self.input.len and self.input[self.pos] == '\n') {
            self.advance();
        }

        const start = self.pos;
        const base_indent = self.column - 1;

        while (self.pos < self.input.len) {
            const line_start = self.pos;
            const indent = self.countIndent();

            if (indent <= base_indent and self.pos < self.input.len and self.input[self.pos] != '\n') {
                self.pos = line_start;
                break;
            }

            while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                self.advance();
            }
            if (self.pos < self.input.len) {
                self.advance();
            }
        }

        const value = self.input[start..self.pos];
        return .{
            .value = value,
            .style = .literal,
        };
    }

    fn scanFolded(self: *Scanner) !Token.Scalar {
        // Similar to literal but folds single newlines
        self.skipWhitespaceOnLine();
        if (self.pos < self.input.len and self.input[self.pos] == '\n') {
            self.advance();
        }

        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        const base_indent = self.column - 1;
        var last_was_newline = false;

        while (self.pos < self.input.len) {
            const line_start = self.pos;
            const indent = self.countIndent();

            if (indent <= base_indent and self.pos < self.input.len and self.input[self.pos] != '\n') {
                self.pos = line_start;
                break;
            }

            const line_content_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                self.advance();
            }

            const line = std.mem.trim(u8, self.input[line_content_start..self.pos], " \t");

            if (line.len == 0) {
                try buf.append(self.allocator, '\n');
                last_was_newline = true;
            } else {
                if (buf.items.len > 0 and !last_was_newline) {
                    try buf.append(self.allocator, ' ');
                }
                try buf.appendSlice(self.allocator, line);
                last_was_newline = false;
            }

            if (self.pos < self.input.len) {
                self.advance();
            }
        }

        const value = try self.allocator.dupe(u8, buf.items);
        return .{
            .value = value,
            .style = .folded,
        };
    }

    fn scanAnchorName(self: *Scanner) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
                break;
            }
            self.advance();
        }
        return self.input[start..self.pos];
    }

    fn scanTag(self: *Scanner) ![]const u8 {
        const start = self.pos;
        self.advance(); // Skip !

        if (self.pos < self.input.len and self.input[self.pos] == '!') {
            // !! prefix for global tags
            self.advance();
        }

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (self.isWhitespace(c)) {
                break;
            }
            self.advance();
        }

        return self.input[start..self.pos];
    }

    fn skipWhitespaceAndComments(self: *Scanner) void {
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '#') {
                // Skip comment until end of line
                while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                    self.advance();
                }
            } else if (self.isWhitespace(c)) {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceOnLine(self: *Scanner) void {
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == ' ' or c == '\t') {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn countIndent(self: *Scanner) usize {
        var count: usize = 0;
        var p = self.pos;
        while (p < self.input.len) {
            const c = self.input[p];
            if (c == ' ') {
                count += 1;
                p += 1;
            } else if (c == '\t') {
                count += 8;
                p += 1;
            } else {
                break;
            }
        }
        self.pos = p;
        self.column += count;
        return count;
    }

    fn isWhitespace(self: *Scanner, c: u8) bool {
        _ = self;
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }

    fn isWhitespaceOrEnd(self: *Scanner, pos: usize) bool {
        if (pos >= self.input.len) return true;
        return self.isWhitespace(self.input[pos]);
    }

    fn advance(self: *Scanner) void {
        if (self.pos < self.input.len) {
            if (self.input[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }
};

test "scanner basic" {
    const testing = std.testing;
    var scanner = try Scanner.init(testing.allocator, "hello");
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token != null);
}
