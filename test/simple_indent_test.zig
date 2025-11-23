const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");

test "simple two-key mapping" {
    const allocator = testing.allocator;

    const yaml_content =
        \\key1: value1
        \\key2: value2
    ;

    var parsed = try yaml.parseFromSlice(allocator, yaml_content);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);
    try testing.expect(root_map.?.get("key1") != null);
    try testing.expect(root_map.?.get("key2") != null);
}

test "mapping with nested sequence - minimal" {
    const allocator = testing.allocator;

    const yaml_content =
        \\first: a
        \\list:
        \\- b
        \\last: c
    ;

    var parsed = try yaml.parseFromSlice(allocator, yaml_content);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    try testing.expect(root_map.?.get("first") != null);
    try testing.expect(root_map.?.get("list") != null);
    try testing.expect(root_map.?.get("last") != null);
}
