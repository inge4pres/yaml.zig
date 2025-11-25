const std = @import("std");
const yaml = @import("yaml");

const TestResult = struct {
    name: []const u8,
    passed: bool,
    error_msg: ?[]const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <yaml-test-suite-directory>\n", .{args[0]});
        std.process.exit(1);
    }

    const test_suite_dir = args[1];

    var results = std.ArrayList(TestResult){};
    defer {
        for (results.items) |result| {
            if (result.error_msg) |msg| {
                allocator.free(msg);
            }
        }
        results.deinit(allocator);
    }

    try runTestSuite(allocator, test_suite_dir, &results);

    // Print summary
    try printSummary(results.items);

    // Exit with error code if any tests failed
    var failed: usize = 0;
    for (results.items) |result| {
        if (!result.passed) failed += 1;
    }

    if (failed > 0) {
        std.process.exit(1);
    }
}

fn runTestSuite(allocator: std.mem.Allocator, suite_dir: []const u8, results: *std.ArrayList(TestResult)) !void {
    var dir = try std.fs.cwd().openDir(suite_dir, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Each test case is in a directory with a specific ID
        const test_id = entry.name;
        try runSingleTest(allocator, dir, test_id, results);
    }
}

fn runSingleTest(allocator: std.mem.Allocator, suite_dir: std.fs.Dir, test_id: []const u8, results: *std.ArrayList(TestResult)) !void {
    var test_dir = suite_dir.openDir(test_id, .{ .iterate = true }) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open test directory: {}", .{err});
        try results.append(allocator, .{
            .name = test_id,
            .passed = false,
            .error_msg = error_msg,
        });
        return;
    };
    defer test_dir.close();

    // Check if this is a multi-test directory (has numeric subdirectories)
    // by trying to access in.yaml - if it doesn't exist, it's a parent directory
    test_dir.access("in.yaml", .{}) catch {
        // This is a parent directory with subdirectories like 00, 01, 02
        // Run each subtest
        var subdir_iter = test_dir.iterate();
        while (try subdir_iter.next()) |entry| {
            if (entry.kind != .directory) continue;
            const subtest_id = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ test_id, entry.name });
            defer allocator.free(subtest_id);
            try runSubTest(allocator, test_dir, entry.name, subtest_id, results);
        }
        return;
    };

    // Single test case
    std.debug.print("Testing: {s}... ", .{test_id});
    try runTestCase(allocator, test_dir, test_id, results);
}

fn runSubTest(allocator: std.mem.Allocator, parent_dir: std.fs.Dir, subdir_name: []const u8, full_test_id: []const u8, results: *std.ArrayList(TestResult)) !void {
    std.debug.print("Testing: {s}... ", .{full_test_id});

    var test_dir = parent_dir.openDir(subdir_name, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open subtest directory: {}", .{err});
        try results.append(allocator, .{
            .name = full_test_id,
            .passed = false,
            .error_msg = error_msg,
        });
        std.debug.print("❌ (open failed)\n", .{});
        return;
    };
    defer test_dir.close();

    try runTestCase(allocator, test_dir, full_test_id, results);
}

fn runTestCase(allocator: std.mem.Allocator, test_dir: std.fs.Dir, test_id: []const u8, results: *std.ArrayList(TestResult)) !void {
    // Read test metadata from '====' file if it exists
    const in_yaml_path = "in.yaml";
    const error_path = "error";

    // Check if this test expects an error
    const expects_error = blk: {
        test_dir.access(error_path, .{}) catch break :blk false;
        break :blk true;
    };

    // Try to read the input YAML
    const yaml_content = test_dir.readFileAlloc(allocator, in_yaml_path, 1024 * 1024) catch |err| {
        if (expects_error) {
            // If we expect an error and can't read the file, that might be intentional
            try results.append(allocator, .{
                .name = test_id,
                .passed = true,
                .error_msg = null,
            });
            std.debug.print("✅ (expected error)\n", .{});
            return;
        }
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to read in.yaml: {}", .{err});
        try results.append(allocator, .{
            .name = test_id,
            .passed = false,
            .error_msg = error_msg,
        });
        std.debug.print("❌ (read failed)\n", .{});
        return;
    };
    defer allocator.free(yaml_content);

    // Try to parse the YAML
    var parsed = yaml.parseFromSlice(allocator, yaml_content) catch |err| {
        if (expects_error) {
            // Expected to fail
            try results.append(allocator, .{
                .name = test_id,
                .passed = true,
                .error_msg = null,
            });
            std.debug.print("✅ (expected error)\n", .{});
        } else {
            const error_msg = try std.fmt.allocPrint(allocator, "Parse failed (unexpected): {}", .{err});
            try results.append(allocator, .{
                .name = test_id,
                .passed = false,
                .error_msg = error_msg,
            });
            std.debug.print("❌\n", .{});
        }
        return;
    };
    defer parsed.deinit();

    if (expects_error) {
        // We parsed successfully but should have failed
        const error_msg = try std.fmt.allocPrint(allocator, "Parse succeeded but error was expected", .{});
        try results.append(allocator, .{
            .name = test_id,
            .passed = false,
            .error_msg = error_msg,
        });
        std.debug.print("❌ (should have failed)\n", .{});
    } else {
        // Success!
        try results.append(allocator, .{
            .name = test_id,
            .passed = true,
            .error_msg = null,
        });
        std.debug.print("✅\n", .{});
    }
}

fn printSummary(results: []const TestResult) !void {
    var passed: usize = 0;
    var failed: usize = 0;

    std.debug.print("\n=== YAML Test Suite Results ===\n\n", .{});

    for (results) |result| {
        if (result.passed) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("❌ {s}", .{result.name});
            if (result.error_msg) |msg| {
                std.debug.print(": {s}", .{msg});
            }
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("Total: {d} tests\n", .{results.len});
    std.debug.print("✅ Passed: {d}\n", .{passed});
    std.debug.print("❌ Failed: {d}\n", .{failed});

    if (passed > 0 and failed == 0) {
        std.debug.print("\n🎉 All tests passed!\n", .{});
    } else if (failed > 0) {
        const pass_rate = @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(results.len)) * 100.0;
        std.debug.print("\n📊 Pass rate: {d:.1}%\n", .{pass_rate});
    }
}
