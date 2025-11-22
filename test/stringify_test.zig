const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");
const Value = yaml.Value;
const stringify = yaml.stringify;

test "stringify: null value" {
    const value = Value{ .null = {} };
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(value, &w.writer);

    try testing.expectEqualStrings("null\n", w.written());
}

test "stringify: boolean values" {
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(Value{ .bool = true }, &w.writer);
    try testing.expectEqualStrings("true\n", w.written());

    w.clearRetainingCapacity();
    try stringify(Value{ .bool = false }, &w.writer);
    try testing.expectEqualStrings("false\n", w.written());
}

test "stringify: integer values" {
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(Value{ .int = 42 }, &w.writer);
    try testing.expectEqualStrings("42\n", w.written());

    w.clearRetainingCapacity();
    try stringify(Value{ .int = -17 }, &w.writer);
    try testing.expectEqualStrings("-17\n", w.written());

    w.clearRetainingCapacity();
    try stringify(Value{ .int = 0 }, &w.writer);
    try testing.expectEqualStrings("0\n", w.written());
}

test "stringify: float values" {
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(Value{ .float = 3.14 }, &w.writer);
    try testing.expect(std.mem.startsWith(u8, w.written(), "3.14"));

    w.clearRetainingCapacity();
    try stringify(Value{ .float = std.math.inf(f64) }, &w.writer);
    try testing.expectEqualStrings(".inf\n", w.written());

    w.clearRetainingCapacity();
    try stringify(Value{ .float = -std.math.inf(f64) }, &w.writer);
    try testing.expectEqualStrings("-.inf\n", w.written());

    w.clearRetainingCapacity();
    try stringify(Value{ .float = std.math.nan(f64) }, &w.writer);
    try testing.expectEqualStrings(".nan\n", w.written());
}

test "stringify: simple strings" {
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    const str = try testing.allocator.dupe(u8, "hello");
    defer testing.allocator.free(str);

    const value = Value{ .string = str };
    try stringify(value, &w.writer);
    try testing.expectEqualStrings("hello\n", w.written());
}

test "stringify: strings with special characters" {
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    const str = try testing.allocator.dupe(u8, "Line 1\nLine 2\tTabbed");
    defer testing.allocator.free(str);

    const value = Value{ .string = str };
    try stringify(value, &w.writer);
    try testing.expectEqualStrings("\"Line 1\\nLine 2\\tTabbed\"\n", w.written());
}

test "stringify: strings that need quoting" {
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    // Test reserved word
    const str1 = try testing.allocator.dupe(u8, "null");
    defer testing.allocator.free(str1);
    try stringify(Value{ .string = str1 }, &w.writer);
    try testing.expectEqualStrings("\"null\"\n", w.written());

    // Test string that looks like number
    w.clearRetainingCapacity();
    const str2 = try testing.allocator.dupe(u8, "123");
    defer testing.allocator.free(str2);
    try stringify(Value{ .string = str2 }, &w.writer);
    try testing.expectEqualStrings("\"123\"\n", w.written());
}

test "stringify: empty sequence" {
    var seq = Value.Sequence{};
    defer seq.deinit(testing.allocator);

    const value = Value{ .sequence = seq };
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(value, &w.writer);
    try testing.expectEqualStrings("[]\n", w.written());
}

test "stringify: simple sequence" {
    var seq = Value.Sequence{};
    try seq.append(testing.allocator, Value{ .int = 1 });
    try seq.append(testing.allocator, Value{ .int = 2 });
    try seq.append(testing.allocator, Value{ .int = 3 });

    var value = Value{ .sequence = seq };
    defer value.deinit(testing.allocator);

    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(value, &w.writer);

    const expected = "- 1\n- 2\n- 3\n";
    try testing.expectEqualStrings(expected, w.written());
}

test "stringify: sequence with strings" {
    const allocator = testing.allocator;
    var seq = Value.Sequence{};

    const str1 = try allocator.dupe(u8, "apple");
    const str2 = try allocator.dupe(u8, "banana");
    const str3 = try allocator.dupe(u8, "cherry");

    try seq.append(allocator, Value{ .string = str1 });
    try seq.append(allocator, Value{ .string = str2 });
    try seq.append(allocator, Value{ .string = str3 });

    var value = Value{ .sequence = seq };
    defer value.deinit(allocator);

    var w = std.Io.Writer.Allocating.init(allocator);
    defer w.deinit();

    try stringify(value, &w.writer);

    const expected = "- apple\n- banana\n- cherry\n";
    try testing.expectEqualStrings(expected, w.written());
}

test "stringify: empty mapping" {
    var map = Value.Mapping.init(testing.allocator);
    defer map.deinit();

    const value = Value{ .mapping = map };
    var w = std.Io.Writer.Allocating.init(testing.allocator);
    defer w.deinit();

    try stringify(value, &w.writer);
    try testing.expectEqualStrings("{}\n", w.written());
}

test "stringify: simple mapping" {
    const allocator = testing.allocator;
    var map = Value.Mapping.init(allocator);

    const key1 = try allocator.dupe(u8, "name");
    const val1 = try allocator.dupe(u8, "yaml.zig");
    try map.put(key1, Value{ .string = val1 });

    const key2 = try allocator.dupe(u8, "count");
    try map.put(key2, Value{ .int = 100 });

    const key3 = try allocator.dupe(u8, "active");
    try map.put(key3, Value{ .bool = true });

    var value = Value{ .mapping = map };
    defer value.deinit(allocator);

    var w = std.Io.Writer.Allocating.init(allocator);
    defer w.deinit();

    try stringify(value, &w.writer);

    // Keys should be sorted: active, count, name
    const expected = "active: true\ncount: 100\nname: yaml.zig\n";
    try testing.expectEqualStrings(expected, w.written());
}

test "stringify: nested mapping" {
    const allocator = testing.allocator;
    var root_map = Value.Mapping.init(allocator);

    var inner_map = Value.Mapping.init(allocator);
    const inner_key = try allocator.dupe(u8, "city");
    const inner_val = try allocator.dupe(u8, "NYC");
    try inner_map.put(inner_key, Value{ .string = inner_val });

    const key = try allocator.dupe(u8, "location");
    try root_map.put(key, Value{ .mapping = inner_map });

    var value = Value{ .mapping = root_map };
    defer value.deinit(allocator);

    var w = std.Io.Writer.Allocating.init(allocator);
    defer w.deinit();

    try stringify(value, &w.writer);

    const expected = "location: \n  city: NYC\n";
    try testing.expectEqualStrings(expected, w.written());
}

test "stringify: roundtrip parse and stringify" {
    const allocator = testing.allocator;

    const input =
        \\name: test
        \\count: 42
        \\enabled: true
    ;

    // Parse
    var parsed = try yaml.parseFromSlice(allocator, input);
    defer parsed.deinit();

    // Stringify
    var w = std.Io.Writer.Allocating.init(allocator);
    defer w.deinit();

    try stringify(parsed.value, &w.writer);

    // Parse again
    var parsed2 = try yaml.parseFromSlice(allocator, w.written());
    defer parsed2.deinit();

    // Verify values match
    var map1 = parsed.value.asMapping().?;
    var map2 = parsed2.value.asMapping().?;

    try testing.expectEqualStrings("test", map1.get("name").?.asString().?);
    try testing.expectEqualStrings("test", map2.get("name").?.asString().?);

    try testing.expectEqual(true, map1.get("enabled").?.asBool().?);
    try testing.expectEqual(true, map2.get("enabled").?.asBool().?);
}

test "stringify: serializeToWriter" {
    const allocator = testing.allocator;

    // Create a simple value
    var map = Value.Mapping.init(allocator);
    const key1 = try allocator.dupe(u8, "name");
    const val1 = try allocator.dupe(u8, "test");
    try map.put(key1, Value{ .string = val1 });

    const key2 = try allocator.dupe(u8, "value");
    try map.put(key2, Value{ .int = 42 });

    var value = Value{ .mapping = map };
    defer value.deinit(allocator);

    var w = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w.deinit();
    const writer = &w.writer;

    try yaml.serializeToWriter(value, writer);

    const expected = "name: test\nvalue: 42\n";
    try testing.expectEqualStrings(expected, w.written());
}

test "stringify: serializeToWriterWithOptions" {
    const allocator = testing.allocator;

    // Create a simple sequence
    var seq = Value.Sequence{};
    try seq.append(allocator, Value{ .int = 1 });
    try seq.append(allocator, Value{ .int = 2 });
    try seq.append(allocator, Value{ .int = 3 });

    var value = Value{ .sequence = seq };
    defer value.deinit(allocator);

    var w = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w.deinit();
    const writer = &w.writer;

    // Use custom options
    const options = yaml.StringifyOptions{
        .indent_size = 4,  // Use 4 spaces instead of 2
    };

    try yaml.serializeToWriterWithOptions(value, writer, options);

    const expected = "- 1\n- 2\n- 3\n";
    try testing.expectEqualStrings(expected, w.written());
}
