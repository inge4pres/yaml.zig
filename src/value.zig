const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic type that can satisy any YAML value.
pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    sequence: Sequence,
    mapping: Mapping,

    /// Collection of YAML values is a list
    pub const Sequence = std.ArrayList(Value);
    /// Representation of a YAML dictionary
    pub const Mapping = std.StringHashMap(Value);

    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .sequence => |*seq| {
                for (seq.items) |*item| {
                    item.deinit(allocator);
                }
                seq.deinit(allocator);
            },
            .mapping => |*map| {
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                map.deinit();
            },
            .string => |s| allocator.free(s),
            else => {},
        }
    }

    // Helper methods for type checking and conversion
    pub fn asBool(self: Value) ?bool {
        return switch (self) {
            .bool => |b| b,
            else => null,
        };
    }

    pub fn asInt(self: Value) ?i64 {
        return switch (self) {
            .int => |i| i,
            else => null,
        };
    }

    pub fn asFloat(self: Value) ?f64 {
        return switch (self) {
            .float => |f| f,
            .int => |i| @floatFromInt(i),
            else => null,
        };
    }

    pub fn asString(self: Value) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            else => null,
        };
    }

    pub fn asSequence(self: *Value) ?*Sequence {
        return switch (self.*) {
            .sequence => |*seq| seq,
            else => null,
        };
    }

    pub fn asMapping(self: *Value) ?*Mapping {
        return switch (self.*) {
            .mapping => |*map| map,
            else => null,
        };
    }

    // Check if value is null
    pub fn isNull(self: Value) bool {
        return self == .null;
    }

    // Create convenience constructors
    pub fn fromBool(b: bool) Value {
        return .{ .bool = b };
    }

    pub fn fromInt(i: i64) Value {
        return .{ .int = i };
    }

    pub fn fromFloat(f: f64) Value {
        return .{ .float = f };
    }

    pub fn fromString(allocator: Allocator, s: []const u8) !Value {
        const owned = try allocator.dupe(u8, s);
        return .{ .string = owned };
    }

    pub fn initSequence(allocator: Allocator) Value {
        _ = allocator;
        return .{ .sequence = Sequence{} };
    }

    pub fn initMapping(allocator: Allocator) Value {
        return .{ .mapping = Mapping.init(allocator) };
    }

    // Format for debugging
    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .null => try writer.writeAll("null"),
            .bool => |b| try writer.print("{}", .{b}),
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .sequence => |seq| {
                try writer.writeAll("[");
                for (seq.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format("", .{}, writer);
                }
                try writer.writeAll("]");
            },
            .mapping => |map| {
                try writer.writeAll("{");
                var iter = map.iterator();
                var first = true;
                while (iter.next()) |entry| {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.print("{s}: ", .{entry.key_ptr.*});
                    try entry.value_ptr.format("", .{}, writer);
                }
                try writer.writeAll("}");
            },
        }
    }
};

test "value creation and cleanup" {
    const testing = std.testing;

    var val = Value{ .int = 42 };
    try testing.expectEqual(@as(i64, 42), val.asInt().?);
    val.deinit(testing.allocator);
}

test "value string ownership" {
    const testing = std.testing;

    var val = try Value.fromString(testing.allocator, "hello");
    try testing.expectEqualStrings("hello", val.asString().?);
    val.deinit(testing.allocator);
}

test "value sequence" {
    const testing = std.testing;

    var val = Value.initSequence(testing.allocator);
    var seq = val.asSequence().?;

    try seq.append(testing.allocator, Value.fromInt(1));
    try seq.append(testing.allocator, Value.fromInt(2));
    try seq.append(testing.allocator, Value.fromInt(3));

    try testing.expectEqual(@as(usize, 3), seq.items.len);
    try testing.expectEqual(@as(i64, 1), seq.items[0].asInt().?);
    try testing.expectEqual(@as(i64, 2), seq.items[1].asInt().?);
    try testing.expectEqual(@as(i64, 3), seq.items[2].asInt().?);

    val.deinit(testing.allocator);
}

test "value mapping" {
    const testing = std.testing;

    var val = Value.initMapping(testing.allocator);
    var map = val.asMapping().?;

    const key1 = try testing.allocator.dupe(u8, "key1");
    try map.put(key1, Value.fromInt(100));

    const key2 = try testing.allocator.dupe(u8, "key2");
    try map.put(key2, Value.fromBool(true));

    try testing.expectEqual(@as(usize, 2), map.count());
    try testing.expectEqual(@as(i64, 100), map.get("key1").?.asInt().?);
    try testing.expectEqual(true, map.get("key2").?.asBool().?);

    val.deinit(testing.allocator);
}

test "value nested structures" {
    const testing = std.testing;

    var root = Value.initMapping(testing.allocator);
    var root_map = root.asMapping().?;

    // Create nested sequence
    var inner_seq = Value.initSequence(testing.allocator);
    var seq = inner_seq.asSequence().?;
    try seq.append(testing.allocator, Value.fromInt(1));
    try seq.append(testing.allocator, Value.fromInt(2));

    const key = try testing.allocator.dupe(u8, "numbers");
    try root_map.put(key, inner_seq);

    try testing.expectEqual(@as(usize, 1), root_map.count());
    var retrieved = root_map.getPtr("numbers").?;
    const retrieved_seq = retrieved.asSequence();
    try testing.expect(retrieved_seq != null);
    try testing.expectEqual(@as(usize, 2), retrieved_seq.?.items.len);

    root.deinit(testing.allocator);
}

test "value type conversions" {
    const testing = std.testing;

    // Int to float conversion
    var int_val = Value.fromInt(42);
    try testing.expectEqual(@as(f64, 42.0), int_val.asFloat().?);

    // Bool checks
    var bool_val = Value.fromBool(true);
    try testing.expectEqual(true, bool_val.asBool().?);
    try testing.expectEqual(null, bool_val.asInt());

    // Null checks
    var null_val = Value{ .null = {} };
    try testing.expect(null_val.isNull());
    try testing.expectEqual(null, null_val.asString());
}
