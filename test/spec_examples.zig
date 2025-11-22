const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");

// YAML 1.2.2 Specification Examples
// These tests validate compliance with official spec examples

test "Example 2.1: Sequence of Scalars" {
    const input =
        \\- Mark McGwire
        \\- Sammy Sosa
        \\- Ken Griffey
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const seq = parsed.value.asSequence();
    try testing.expect(seq != null);
    try testing.expectEqual(@as(usize, 3), seq.?.items.len);
}

test "Example 2.2: Mapping Scalars to Scalars" {
    const input =
        \\hr: 65
        \\avg: 0.278
        \\rbi: 147
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 3), map.?.count());
}

test "Example 2.5: Sequence of Sequences" {
    const input =
        \\- [name, hr, avg]
        \\- [Mark McGwire, 65, 0.278]
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const outer_seq = parsed.value.asSequence();
    try testing.expect(outer_seq != null);
    try testing.expectEqual(@as(usize, 2), outer_seq.?.items.len);
}

test "Example 2.6: Mapping of Mappings" {
    const input =
        \\Mark McGwire: {hr: 65, avg: 0.278}
        \\Sammy Sosa: {hr: 63, avg: 0.288}
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const map = parsed.value.asMapping();
    try testing.expect(map != null);
    try testing.expectEqual(@as(usize, 2), map.?.count());
}

// TODO: Add more spec examples from YAML 1.2.2
