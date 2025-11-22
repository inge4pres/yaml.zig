const std = @import("std");
const testing = std.testing;
const Value = @import("yaml").Value;

test "create and destroy scalar values" {
    var val = Value{ .int = 42 };
    try testing.expectEqual(@as(i64, 42), val.asInt().?);
    val.deinit(testing.allocator);
}

test "create and destroy string value" {
    var val = try Value.fromString(testing.allocator, "test string");
    try testing.expectEqualStrings("test string", val.asString().?);
    val.deinit(testing.allocator);
}

test "create and destroy sequence" {
    var val = Value.initSequence(testing.allocator);
    var seq = val.asSequence().?;

    try seq.append(testing.allocator, Value.fromInt(1));
    try seq.append(testing.allocator, Value.fromInt(2));
    try seq.append(testing.allocator, try Value.fromString(testing.allocator, "three"));

    try testing.expectEqual(@as(usize, 3), seq.items.len);
    val.deinit(testing.allocator);
}

test "create and destroy mapping" {
    var val = Value.initMapping(testing.allocator);
    var map = val.asMapping().?;

    const k1 = try testing.allocator.dupe(u8, "name");
    try map.put(k1, try Value.fromString(testing.allocator, "Alice"));

    const k2 = try testing.allocator.dupe(u8, "age");
    try map.put(k2, Value.fromInt(30));

    try testing.expectEqual(@as(usize, 2), map.count());
    val.deinit(testing.allocator);
}

test "nested structures memory management" {
    var root = Value.initMapping(testing.allocator);
    var root_map = root.asMapping().?;

    // Nested mapping
    var person = Value.initMapping(testing.allocator);
    var person_map = person.asMapping().?;

    const name_key = try testing.allocator.dupe(u8, "name");
    try person_map.put(name_key, try Value.fromString(testing.allocator, "Bob"));

    // Nested sequence
    var hobbies = Value.initSequence(testing.allocator);
    var hobbies_seq = hobbies.asSequence().?;
    try hobbies_seq.append(testing.allocator, try Value.fromString(testing.allocator, "reading"));
    try hobbies_seq.append(testing.allocator, try Value.fromString(testing.allocator, "coding"));

    const hobbies_key = try testing.allocator.dupe(u8, "hobbies");
    try person_map.put(hobbies_key, hobbies);

    const person_key = try testing.allocator.dupe(u8, "person");
    try root_map.put(person_key, person);

    // Verify structure
    var retrieved_person = root_map.getPtr("person").?;
    const retrieved_person_map = retrieved_person.asMapping();
    try testing.expect(retrieved_person_map != null);
    try testing.expectEqual(@as(usize, 2), retrieved_person_map.?.count());

    // Clean up everything
    root.deinit(testing.allocator);
}

test "value bool helpers" {
    var true_val = Value.fromBool(true);
    var false_val = Value.fromBool(false);

    try testing.expectEqual(true, true_val.asBool().?);
    try testing.expectEqual(false, false_val.asBool().?);

    true_val.deinit(testing.allocator);
    false_val.deinit(testing.allocator);
}

test "value null checks" {
    var null_val = Value{ .null = {} };

    try testing.expect(null_val.isNull());
    try testing.expectEqual(null, null_val.asBool());
    try testing.expectEqual(null, null_val.asInt());
    try testing.expectEqual(null, null_val.asFloat());
    try testing.expectEqual(null, null_val.asString());

    null_val.deinit(testing.allocator);
}

test "value int to float conversion" {
    var int_val = Value.fromInt(100);

    try testing.expectEqual(@as(i64, 100), int_val.asInt().?);
    try testing.expectEqual(@as(f64, 100.0), int_val.asFloat().?);

    int_val.deinit(testing.allocator);
}

test "value float precision" {
    var float_val = Value.fromFloat(3.14159);

    try testing.expectEqual(@as(f64, 3.14159), float_val.asFloat().?);
    try testing.expectEqual(null, float_val.asInt());

    float_val.deinit(testing.allocator);
}
