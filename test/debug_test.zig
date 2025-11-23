const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");

test "simple mapping with sequence then scalar" {
    const allocator = testing.allocator;

    const yaml_content =
        \\key1: value1
        \\key2:
        \\- item1
        \\- item2
        \\key3: value3
    ;

    var parsed = try yaml.parseFromSlice(allocator, yaml_content);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    // All three keys should exist
    try testing.expect(root_map.?.get("key1") != null);
    try testing.expect(root_map.?.get("key2") != null);
    try testing.expect(root_map.?.get("key3") != null);
}

test "mapping with multiple sequences" {
    const allocator = testing.allocator;

    const yaml_content =
        \\first: value1
        \\list1:
        \\- a
        \\- b
        \\middle: value2
        \\list2:
        \\- c
        \\- d
        \\last: value3
    ;

    var parsed = try yaml.parseFromSlice(allocator, yaml_content);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    try testing.expect(root_map.?.get("first") != null);
    try testing.expect(root_map.?.get("list1") != null);
    try testing.expect(root_map.?.get("middle") != null);
    try testing.expect(root_map.?.get("list2") != null);
    try testing.expect(root_map.?.get("last") != null);
}

test "mapping with sequences of mappings" {
    const allocator = testing.allocator;

    const yaml_content =
        \\apiVersion: v1
        \\clusters:
        \\- cluster:
        \\    server: https://example.com
        \\  name: test-cluster
        \\contexts:
        \\- context:
        \\    cluster: test-cluster
        \\  name: test-context
        \\current-context: test-context
    ;

    var parsed = try yaml.parseFromSlice(allocator, yaml_content);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    try testing.expect(root_map.?.get("apiVersion") != null);
    try testing.expect(root_map.?.get("clusters") != null);
    try testing.expect(root_map.?.get("contexts") != null);
    try testing.expect(root_map.?.get("current-context") != null);
}
