const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");

test "parse kubeconfig file" {
    const allocator = testing.allocator;

    // Read the actual kubeconfig file
    const file = try std.fs.openFileAbsolute("/home/francesco/.kube/config", .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    var parsed = try yaml.parseFromSlice(allocator, content);
    defer parsed.deinit();

    // The root should be a mapping
    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    // Check if current-context exists
    const current_context = root_map.?.get("current-context");
    try testing.expect(current_context != null);

    // If we get here, verify it's the expected value
    const context_str = current_context.?.asString();
    try testing.expect(context_str != null);
    try testing.expectEqualStrings("hotel", context_str.?);
}

test "parse minimal kubeconfig structure" {
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
        \\kind: Config
        \\preferences: {}
        \\users:
        \\- name: test-user
        \\  user:
        \\    token: test-token
    ;

    var parsed = try yaml.parseFromSlice(allocator, yaml_content);
    defer parsed.deinit();

    const root_map = parsed.value.asMapping();
    try testing.expect(root_map != null);

    // Verify all top-level keys exist
    try testing.expect(root_map.?.get("apiVersion") != null);
    try testing.expect(root_map.?.get("clusters") != null);
    try testing.expect(root_map.?.get("contexts") != null);
    try testing.expect(root_map.?.get("current-context") != null);
    try testing.expect(root_map.?.get("kind") != null);
    try testing.expect(root_map.?.get("preferences") != null);
    try testing.expect(root_map.?.get("users") != null);

    // Check current-context value
    const current_context = root_map.?.get("current-context").?;
    const context_str = current_context.asString();
    try testing.expect(context_str != null);
    try testing.expectEqualStrings("test-context", context_str.?);
}
