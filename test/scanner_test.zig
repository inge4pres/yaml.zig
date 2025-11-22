const std = @import("std");
const testing = std.testing;
const Scanner = @import("yaml").Scanner;
const Token = @import("yaml").Scanner.Token;

test "scan empty document" {
    var scanner = try Scanner.init(testing.allocator, "");
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token != null);
    try testing.expect(token.? == .stream_end);
}

test "scan simple scalar" {
    var scanner = try Scanner.init(testing.allocator, "hello");
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token != null);
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("hello", token.?.scalar.value);
    try testing.expect(token.?.scalar.style == .plain);
}

test "scan block sequence" {
    const input = "- a\n- b\n- c";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    // First item
    var token = try scanner.next();
    try testing.expect(token.? == .block_entry);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("a", token.?.scalar.value);

    // Second item
    token = try scanner.next();
    try testing.expect(token.? == .block_entry);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("b", token.?.scalar.value);

    // Third item
    token = try scanner.next();
    try testing.expect(token.? == .block_entry);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("c", token.?.scalar.value);
}

test "scan block mapping" {
    const input = "key1: value1\nkey2: value2";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    // First pair
    var token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("key1", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .value);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("value1", token.?.scalar.value);

    // Second pair
    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("key2", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .value);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("value2", token.?.scalar.value);
}

test "scan flow sequence" {
    const input = "[1, 2, 3]";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .flow_sequence_start);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("1", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .flow_entry);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("2", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .flow_entry);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("3", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .flow_sequence_end);
}

test "scan flow mapping" {
    const input = "{a: 1, b: 2}";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .flow_mapping_start);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("a", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .value);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("1", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .flow_entry);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("b", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .value);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("2", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .flow_mapping_end);
}

test "scan single quoted string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "'it''s a test'";
    var scanner = try Scanner.init(allocator, input);
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("it's a test", token.?.scalar.value);
    try testing.expect(token.?.scalar.style == .single_quoted);
}

test "scan double quoted string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "\"line1\\nline2\\ttab\"";
    var scanner = try Scanner.init(allocator, input);
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("line1\nline2\ttab", token.?.scalar.value);
    try testing.expect(token.?.scalar.style == .double_quoted);
}

test "scan document markers" {
    const input = "---\nfoo\n...\n---\nbar";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .document_start);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("foo", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .document_end);

    token = try scanner.next();
    try testing.expect(token.? == .document_start);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("bar", token.?.scalar.value);
}

test "scan anchors and aliases" {
    const input = "&anchor value\n*anchor";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .anchor);
    try testing.expectEqualStrings("anchor", token.?.anchor);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("value", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .alias);
    try testing.expectEqualStrings("anchor", token.?.alias);
}

test "scan tags" {
    const input = "!!str 123";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .tag);
    try testing.expectEqualStrings("!!str", token.?.tag);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("123", token.?.scalar.value);
}

test "scan with comments" {
    const input = "key: value # this is a comment";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("key", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .value);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("value", token.?.scalar.value);

    // Comment should be skipped
    token = try scanner.next();
    try testing.expect(token == null or token.? == .stream_end);
}

test "scan literal block scalar" {
    const input = "|\n  line1\n  line2";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expect(token.?.scalar.style == .literal);
    try testing.expect(std.mem.indexOf(u8, token.?.scalar.value, "line1") != null);
    try testing.expect(std.mem.indexOf(u8, token.?.scalar.value, "line2") != null);
}

test "scan folded block scalar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ">\n  line1\n  line2";
    var scanner = try Scanner.init(allocator, input);
    defer scanner.deinit();

    const token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expect(token.?.scalar.style == .folded);
}

test "scan explicit key indicator" {
    const input = "? key\n: value";
    var scanner = try Scanner.init(testing.allocator, input);
    defer scanner.deinit();

    var token = try scanner.next();
    try testing.expect(token.? == .key);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("key", token.?.scalar.value);

    token = try scanner.next();
    try testing.expect(token.? == .value);

    token = try scanner.next();
    try testing.expect(token.? == .scalar);
    try testing.expectEqualStrings("value", token.?.scalar.value);
}
