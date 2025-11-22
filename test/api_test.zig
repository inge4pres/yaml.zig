const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");

// High-level API tests using the public parseFromSlice interface
// These tests validate the complete parsing pipeline from user perspective

test "api: parse simple scalar" {
    var parsed = try yaml.parseFromSlice(testing.allocator, "hello world");
    defer parsed.deinit();

    try testing.expectEqualStrings("hello world", parsed.value.asString().?);
}

test "api: parse simple mapping" {
    const input =
        \\name: yaml.zig
        \\count: 100
        \\active: true
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping().?;
    try testing.expectEqual(@as(usize, 3), map.count());
    try testing.expectEqualStrings("yaml.zig", map.get("name").?.asString().?);
    try testing.expectEqual(@as(i64, 100), map.get("count").?.asInt().?);
    try testing.expectEqual(true, map.get("active").?.asBool().?);
}

test "api: parse simple sequence" {
    const input =
        \\- apple
        \\- banana
        \\- cherry
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence().?;
    try testing.expectEqual(@as(usize, 3), seq.items.len);
    try testing.expectEqualStrings("apple", seq.items[0].asString().?);
    try testing.expectEqualStrings("banana", seq.items[1].asString().?);
    try testing.expectEqualStrings("cherry", seq.items[2].asString().?);
}

test "api: parse nested structures" {
    const input =
        \\person:
        \\  name: John Doe
        \\  age: 30
        \\  hobbies:
        \\    - coding
        \\    - reading
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var person = root.getPtr("person").?;
    const person_map = person.asMapping().?;

    try testing.expectEqualStrings("John Doe", person_map.get("name").?.asString().?);
    try testing.expectEqual(@as(i64, 30), person_map.get("age").?.asInt().?);

    var hobbies = person_map.getPtr("hobbies").?;
    const hobbies_seq = hobbies.asSequence().?;
    try testing.expectEqual(@as(usize, 2), hobbies_seq.items.len);
    try testing.expectEqualStrings("coding", hobbies_seq.items[0].asString().?);
}

test "api: parse flow style" {
    const input = "[1, 2, 3, {name: test, active: true}]";

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence().?;
    try testing.expectEqual(@as(usize, 4), seq.items.len);
    try testing.expectEqual(@as(i64, 1), seq.items[0].asInt().?);
    try testing.expectEqual(@as(i64, 2), seq.items[1].asInt().?);
    try testing.expectEqual(@as(i64, 3), seq.items[2].asInt().?);

    var last_item = &seq.items[3];
    const map = last_item.asMapping().?;
    try testing.expectEqualStrings("test", map.get("name").?.asString().?);
    try testing.expectEqual(true, map.get("active").?.asBool().?);
}

test "api: parse deeply nested mapping" {
    const input =
        \\server:
        \\  database:
        \\    connection:
        \\      host: localhost
        \\      port: 5432
        \\      timeout: 30
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var server = root.getPtr("server").?;
    const server_map = server.asMapping().?;

    var database = server_map.getPtr("database").?;
    const db_map = database.asMapping().?;

    var connection = db_map.getPtr("connection").?;
    const conn_map = connection.asMapping().?;

    try testing.expectEqualStrings("localhost", conn_map.get("host").?.asString().?);
    try testing.expectEqual(@as(i64, 5432), conn_map.get("port").?.asInt().?);
    try testing.expectEqual(@as(i64, 30), conn_map.get("timeout").?.asInt().?);
}

test "api: parse document markers" {
    const input =
        \\---
        \\name: test
        \\build: 42
        \\...
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping().?;
    try testing.expectEqual(@as(usize, 2), map.count());
    try testing.expectEqualStrings("test", map.get("name").?.asString().?);
    try testing.expectEqual(@as(i64, 42), map.get("build").?.asInt().?);
}

test "api: parse various number formats" {
    const input =
        \\decimal: 42
        \\octal: 0o755
        \\hex: 0xFF
        \\float: 3.14
        \\scientific: 1.23e-4
        \\infinity: .inf
        \\not_a_number: .nan
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping().?;
    try testing.expectEqual(@as(i64, 42), map.get("decimal").?.asInt().?);
    try testing.expectEqual(@as(i64, 0o755), map.get("octal").?.asInt().?);
    try testing.expectEqual(@as(i64, 0xFF), map.get("hex").?.asInt().?);
    try testing.expectEqual(@as(f64, 3.14), map.get("float").?.asFloat().?);

    const inf = map.get("infinity").?.asFloat().?;
    try testing.expect(std.math.isInf(inf));

    const nan = map.get("not_a_number").?.asFloat().?;
    try testing.expect(std.math.isNan(nan));
}

test "api: parse quoted strings with escapes" {
    const input =
        \\single: 'It''s a test'
        \\double: "Line 1\nLine 2\tTabbed"
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping().?;
    try testing.expectEqualStrings("It's a test", map.get("single").?.asString().?);
    try testing.expectEqualStrings("Line 1\nLine 2\tTabbed", map.get("double").?.asString().?);
}

test "api: parse block scalars" {
    const input =
        \\literal: |
        \\  Line 1
        \\  Line 2
        \\  Line 3
        \\folded: >
        \\  This is a long
        \\  line that will
        \\  be folded
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping().?;
    const literal = map.get("literal").?.asString().?;
    try testing.expect(std.mem.indexOf(u8, literal, "\n") != null);

    const folded = map.get("folded").?.asString().?;
    try testing.expect(std.mem.indexOf(u8, folded, "This is a long line") != null);
}

test "api: parse empty collections" {
    const input =
        \\empty_seq: []
        \\empty_map: {}
        \\null_value: null
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping().?;

    var empty_seq = map.getPtr("empty_seq").?;
    const seq = empty_seq.asSequence().?;
    try testing.expectEqual(@as(usize, 0), seq.items.len);

    var empty_map = map.getPtr("empty_map").?;
    const inner_map = empty_map.asMapping().?;
    try testing.expectEqual(@as(usize, 0), inner_map.count());

    try testing.expect(map.get("null_value").?.isNull());
}

test "api: memory cleanup" {
    // This test ensures proper cleanup with arena allocator
    const input =
        \\data:
        \\  - item1
        \\  - item2
        \\  - nested:
        \\      key: value
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    // Just verify structure is correct
    const map = parsed.value.asMapping().?;
    try testing.expectEqual(@as(usize, 1), map.count());
    // Memory will be checked by testing.allocator
}
