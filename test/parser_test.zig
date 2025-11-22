const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");
const parseFromSlice = yaml.parseFromSlice;

test "parse null values" {
    {
        var parsed = try parseFromSlice(testing.allocator, "null");
        defer parsed.deinit();
        try testing.expect(parsed.value.isNull());
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "~");
        defer parsed.deinit();
        try testing.expect(parsed.value.isNull());
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "");
        defer parsed.deinit();
        try testing.expect(parsed.value.isNull());
    }
}

test "parse boolean values" {
    {
        var parsed = try parseFromSlice(testing.allocator, "true");
        defer parsed.deinit();
        try testing.expectEqual(true, parsed.value.asBool().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "false");
        defer parsed.deinit();
        try testing.expectEqual(false, parsed.value.asBool().?);
    }
}

test "parse integers" {
    {
        var parsed = try parseFromSlice(testing.allocator, "42");
        defer parsed.deinit();
        try testing.expectEqual(@as(i64, 42), parsed.value.asInt().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "-17");
        defer parsed.deinit();
        try testing.expectEqual(@as(i64, -17), parsed.value.asInt().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "0o755");
        defer parsed.deinit();
        try testing.expectEqual(@as(i64, 493), parsed.value.asInt().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "0xFF");
        defer parsed.deinit();
        try testing.expectEqual(@as(i64, 255), parsed.value.asInt().?);
    }
}

test "parse floats" {
    {
        var parsed = try parseFromSlice(testing.allocator, "3.14");
        defer parsed.deinit();
        try testing.expectEqual(@as(f64, 3.14), parsed.value.asFloat().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, ".inf");
        defer parsed.deinit();
        try testing.expectEqual(std.math.inf(f64), parsed.value.asFloat().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "-.inf");
        defer parsed.deinit();
        try testing.expectEqual(-std.math.inf(f64), parsed.value.asFloat().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, ".nan");
        defer parsed.deinit();
        try testing.expect(std.math.isNan(parsed.value.asFloat().?));
    }
}

test "parse strings" {
    {
        var parsed = try parseFromSlice(testing.allocator, "hello");
        defer parsed.deinit();
        try testing.expectEqualStrings("hello", parsed.value.asString().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "'it''s'");
        defer parsed.deinit();
        try testing.expectEqualStrings("it's", parsed.value.asString().?);
    }

    {
        var parsed = try parseFromSlice(testing.allocator, "\"line1\\nline2\"");
        defer parsed.deinit();
        try testing.expectEqualStrings("line1\nline2", parsed.value.asString().?);
    }
}

test "parse sequences" {
    const input = "- a\n- b\n- c";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence();
    try testing.expect(seq != null);
    try testing.expectEqual(@as(usize, 3), seq.?.items.len);
    try testing.expectEqualStrings("a", seq.?.items[0].asString().?);
    try testing.expectEqualStrings("b", seq.?.items[1].asString().?);
    try testing.expectEqualStrings("c", seq.?.items[2].asString().?);
}

test "parse mappings" {
    const input = "key1: value1\nkey2: value2";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 2), map.?.count());

    const val1 = map.?.get("key1");
    try testing.expect(val1 != null);
    try testing.expectEqualStrings("value1", val1.?.asString().?);

    const val2 = map.?.get("key2");
    try testing.expect(val2 != null);
    try testing.expectEqualStrings("value2", val2.?.asString().?);
}

test "parse nested structures" {
    const input =
        \\person:
        \\  name: John
        \\  age: 30
        \\  hobbies:
        \\    - reading
        \\    - coding
    ;
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    var person = root_map.?.get("person");
    try testing.expect(person != null);

    var person_map = person.?.asMapping();
    try testing.expect(person_map != null);

    const name = person_map.?.get("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("John", name.?.asString().?);

    const age = person_map.?.get("age");
    try testing.expect(age != null);
    try testing.expectEqual(@as(i64, 30), age.?.asInt().?);

    var hobbies = person_map.?.get("hobbies");
    try testing.expect(hobbies != null);

    const hobbies_seq = hobbies.?.asSequence();
    try testing.expect(hobbies_seq != null);
    try testing.expectEqual(@as(usize, 2), hobbies_seq.?.items.len);
}

test "parse flow sequence" {
    const input = "[1, 2, 3]";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence();
    try testing.expect(seq != null);
    try testing.expectEqual(@as(usize, 3), seq.?.items.len);
    try testing.expectEqual(@as(i64, 1), seq.?.items[0].asInt().?);
    try testing.expectEqual(@as(i64, 2), seq.?.items[1].asInt().?);
    try testing.expectEqual(@as(i64, 3), seq.?.items[2].asInt().?);
}

test "parse flow mapping" {
    const input = "{a: 1, b: 2}";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 2), map.?.count());
}

test "parse with document markers" {
    const input = "---\nfoo: bar";
    var parsed = try parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 1), map.?.count());
}
