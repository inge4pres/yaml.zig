const std = @import("std");
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;

pub const SchemaError = error{
    InvalidBool,
    InvalidInt,
    InvalidFloat,
    InvalidTag,
    OutOfMemory,
};

/// Resolve a scalar value according to YAML 1.2.2 JSON Schema
pub fn resolveScalar(allocator: Allocator, value: []const u8, tag: ?[]const u8) !Value {
    if (tag) |t| {
        // Explicit tag handling
        if (std.mem.eql(u8, t, "!!null")) return .{ .null = {} };
        if (std.mem.eql(u8, t, "!!bool")) return try parseBool(value);
        if (std.mem.eql(u8, t, "!!int")) return try parseInt(value);
        if (std.mem.eql(u8, t, "!!float")) return try parseFloat(value);
        if (std.mem.eql(u8, t, "!!str")) return try Value.fromString(allocator, value);

        // Unknown tag defaults to string
        return try Value.fromString(allocator, value);
    }

    // Implicit resolution (JSON Schema rules)
    if (isNull(value)) return .{ .null = {} };
    if (isBool(value)) return try parseBool(value);
    if (isInt(value)) return try parseInt(value);
    if (isFloat(value)) return try parseFloat(value);

    // Default to string
    return try Value.fromString(allocator, value);
}

fn isNull(value: []const u8) bool {
    if (value.len == 0) return true;
    return std.mem.eql(u8, value, "null") or
        std.mem.eql(u8, value, "~") or
        std.mem.eql(u8, value, "Null") or
        std.mem.eql(u8, value, "NULL");
}

fn isBool(value: []const u8) bool {
    return std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "True") or
        std.mem.eql(u8, value, "False") or
        std.mem.eql(u8, value, "TRUE") or
        std.mem.eql(u8, value, "FALSE");
}

fn isInt(value: []const u8) bool {
    if (value.len == 0) return false;

    // Check for hex
    if (std.mem.startsWith(u8, value, "0x") or std.mem.startsWith(u8, value, "0X")) {
        if (value.len <= 2) return false;
        for (value[2..]) |c| {
            if (!std.ascii.isHex(c) and c != '_') return false;
        }
        return true;
    }

    // Check for octal
    if (std.mem.startsWith(u8, value, "0o") or std.mem.startsWith(u8, value, "0O")) {
        if (value.len <= 2) return false;
        for (value[2..]) |c| {
            if ((c < '0' or c > '7') and c != '_') return false;
        }
        return true;
    }

    // Check for decimal
    var idx: usize = 0;
    if (value[0] == '-' or value[0] == '+') {
        idx = 1;
        if (value.len == 1) return false;
    }

    for (value[idx..]) |c| {
        if (!std.ascii.isDigit(c) and c != '_') return false;
    }

    return true;
}

fn isFloat(value: []const u8) bool {
    if (value.len == 0) return false;

    // Special float values
    if (std.mem.eql(u8, value, ".inf") or
        std.mem.eql(u8, value, ".Inf") or
        std.mem.eql(u8, value, ".INF") or
        std.mem.eql(u8, value, "+.inf") or
        std.mem.eql(u8, value, "+.Inf") or
        std.mem.eql(u8, value, "+.INF"))
    {
        return true;
    }

    if (std.mem.eql(u8, value, "-.inf") or
        std.mem.eql(u8, value, "-.Inf") or
        std.mem.eql(u8, value, "-.INF"))
    {
        return true;
    }

    if (std.mem.eql(u8, value, ".nan") or
        std.mem.eql(u8, value, ".NaN") or
        std.mem.eql(u8, value, ".NAN"))
    {
        return true;
    }

    // Check for regular float pattern
    var has_dot = false;
    var has_e = false;
    var idx: usize = 0;

    if (value[0] == '-' or value[0] == '+') {
        idx = 1;
        if (value.len == 1) return false;
    }

    for (value[idx..]) |c| {
        if (c == '.') {
            if (has_dot or has_e) return false;
            has_dot = true;
        } else if (c == 'e' or c == 'E') {
            if (has_e) return false;
            has_e = true;
            // After 'e', we can have +/- followed by digits
        } else if (c == '+' or c == '-') {
            // Only valid after 'e'
            if (!has_e) return false;
        } else if (!std.ascii.isDigit(c) and c != '_') {
            return false;
        }
    }

    return has_dot or has_e;
}

fn parseBool(value: []const u8) !Value {
    if (std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "True") or
        std.mem.eql(u8, value, "TRUE"))
    {
        return .{ .bool = true };
    }

    if (std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "False") or
        std.mem.eql(u8, value, "FALSE"))
    {
        return .{ .bool = false };
    }

    return SchemaError.InvalidBool;
}

fn parseInt(value: []const u8) !Value {
    // Remove underscores
    var cleaned = std.ArrayList(u8){};
    defer cleaned.deinit(std.heap.page_allocator);

    for (value) |c| {
        if (c != '_') try cleaned.append(std.heap.page_allocator, c);
    }

    const clean_value = cleaned.items;

    // Parse hex
    if (std.mem.startsWith(u8, clean_value, "0x") or std.mem.startsWith(u8, clean_value, "0X")) {
        const parsed = std.fmt.parseInt(i64, clean_value[2..], 16) catch return SchemaError.InvalidInt;
        return .{ .int = parsed };
    }

    // Parse octal
    if (std.mem.startsWith(u8, clean_value, "0o") or std.mem.startsWith(u8, clean_value, "0O")) {
        const parsed = std.fmt.parseInt(i64, clean_value[2..], 8) catch return SchemaError.InvalidInt;
        return .{ .int = parsed };
    }

    // Parse decimal
    const parsed = std.fmt.parseInt(i64, clean_value, 10) catch return SchemaError.InvalidInt;
    return .{ .int = parsed };
}

fn parseFloat(value: []const u8) !Value {
    // Special values
    if (std.mem.eql(u8, value, ".inf") or
        std.mem.eql(u8, value, ".Inf") or
        std.mem.eql(u8, value, ".INF") or
        std.mem.eql(u8, value, "+.inf") or
        std.mem.eql(u8, value, "+.Inf") or
        std.mem.eql(u8, value, "+.INF"))
    {
        return .{ .float = std.math.inf(f64) };
    }

    if (std.mem.eql(u8, value, "-.inf") or
        std.mem.eql(u8, value, "-.Inf") or
        std.mem.eql(u8, value, "-.INF"))
    {
        return .{ .float = -std.math.inf(f64) };
    }

    if (std.mem.eql(u8, value, ".nan") or
        std.mem.eql(u8, value, ".NaN") or
        std.mem.eql(u8, value, ".NAN"))
    {
        return .{ .float = std.math.nan(f64) };
    }

    // Remove underscores
    var cleaned = std.ArrayList(u8){};
    defer cleaned.deinit(std.heap.page_allocator);

    for (value) |c| {
        if (c != '_') try cleaned.append(std.heap.page_allocator, c);
    }

    const parsed = std.fmt.parseFloat(f64, cleaned.items) catch return SchemaError.InvalidFloat;
    return .{ .float = parsed };
}

// Tests
const testing = std.testing;

test "resolve null values" {
    var val = try resolveScalar(testing.allocator, "null", null);
    defer val.deinit(testing.allocator);
    try testing.expect(val.isNull());

    val = try resolveScalar(testing.allocator, "~", null);
    defer val.deinit(testing.allocator);
    try testing.expect(val.isNull());

    val = try resolveScalar(testing.allocator, "", null);
    defer val.deinit(testing.allocator);
    try testing.expect(val.isNull());
}

test "resolve boolean values" {
    var val = try resolveScalar(testing.allocator, "true", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(true, val.asBool().?);

    val = try resolveScalar(testing.allocator, "false", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(false, val.asBool().?);

    val = try resolveScalar(testing.allocator, "True", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(true, val.asBool().?);
}

test "resolve integer values" {
    var val = try resolveScalar(testing.allocator, "42", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(@as(i64, 42), val.asInt().?);

    val = try resolveScalar(testing.allocator, "-17", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(@as(i64, -17), val.asInt().?);

    val = try resolveScalar(testing.allocator, "0o755", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(@as(i64, 493), val.asInt().?);

    val = try resolveScalar(testing.allocator, "0xFF", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(@as(i64, 255), val.asInt().?);

    val = try resolveScalar(testing.allocator, "1_000_000", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(@as(i64, 1000000), val.asInt().?);
}

test "resolve float values" {
    var val = try resolveScalar(testing.allocator, "3.14", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(@as(f64, 3.14), val.asFloat().?);

    val = try resolveScalar(testing.allocator, "1.23e-4", null);
    defer val.deinit(testing.allocator);
    try testing.expect(@abs(val.asFloat().? - 0.000123) < 0.0000001);

    val = try resolveScalar(testing.allocator, ".inf", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(std.math.inf(f64), val.asFloat().?);

    val = try resolveScalar(testing.allocator, "-.inf", null);
    defer val.deinit(testing.allocator);
    try testing.expectEqual(-std.math.inf(f64), val.asFloat().?);

    val = try resolveScalar(testing.allocator, ".nan", null);
    defer val.deinit(testing.allocator);
    try testing.expect(std.math.isNan(val.asFloat().?));
}

test "resolve string values" {
    {
        var val = try resolveScalar(testing.allocator, "hello world", null);
        defer val.deinit(testing.allocator);
        try testing.expectEqualStrings("hello world", val.asString().?);
    }

    {
        var val = try resolveScalar(testing.allocator, "not_a_number", null);
        defer val.deinit(testing.allocator);
        try testing.expectEqualStrings("not_a_number", val.asString().?);
    }
}

test "explicit tags override implicit resolution" {
    {
        var val = try resolveScalar(testing.allocator, "123", "!!str");
        defer val.deinit(testing.allocator);
        try testing.expectEqualStrings("123", val.asString().?);
    }

    {
        var val = try resolveScalar(testing.allocator, "true", "!!str");
        defer val.deinit(testing.allocator);
        try testing.expectEqualStrings("true", val.asString().?);
    }
}
