const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const yaml_mod = b.addModule("yaml", .{
        .root_source_file = b.path("src/yaml.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "yaml",
        .root_module = yaml_mod,
    });
    const lib_install = b.addInstallArtifact(lib, .{});

    b.getInstallStep().dependOn(&lib_install.step);

    // Create test executable
    const main_tests = b.addTest(.{
        .name = "yaml-test",
        .root_module = yaml_mod,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // Additional test files
    const test_files = [_][]const u8{
        "test/scanner_test.zig",
        "test/value_test.zig",
        "test/parser_test.zig",
        "test/api_test.zig",
        "test/spec_examples.zig",
        "test/text_inputs.zig",
        "test/stringify_test.zig",
    };

    for (test_files) |test_file| {
        const t = b.addTest(.{
            .name = std.fs.path.basename(test_file),
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "yaml", .module = yaml_mod },
                },
            }),
        });
        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }
}
