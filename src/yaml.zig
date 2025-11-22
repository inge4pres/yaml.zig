const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export core types
pub const Value = @import("value.zig").Value;
pub const Scanner = @import("scanner.zig").Scanner;
pub const Parser = @import("parser.zig").Parser;

// Main API functions
pub const Parsed = @import("parser.zig").Parsed;
pub const parseFromSlice = @import("parser.zig").parseFromSlice;
pub const stringify = @import("stringify.zig").stringify;
pub const StringifyOptions = @import("stringify.zig").StringifyOptions;
pub const stringifyWithOptions = @import("stringify.zig").stringifyWithOptions;

/// Parse YAML from a file
pub fn parseFromFile(allocator: Allocator, file_path: []const u8) !Parsed {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    return parseFromSlice(allocator, content);
}

/// Serialize Value to a file
pub fn serializeToFile(value: Value, file_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try stringify(value, file.writer());
}

/// Serialize Value to a file with custom options
pub fn serializeToFileWithOptions(value: Value, file_path: []const u8, options: StringifyOptions) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try stringifyWithOptions(value, file.writer(), options);
}

/// Serialize Value to a std.Io.Writer
/// This is useful when you need a uniform writer interface
pub fn serializeToWriter(value: Value, writer: *std.Io.Writer) !void {
    try stringify(value, writer);
}

/// Serialize Value to an AnyWriter with custom options
pub fn serializeToWriterWithOptions(value: Value, writer: *std.Io.Writer, options: StringifyOptions) !void {
    try stringifyWithOptions(value, writer, options);
}

test {
    // Import all test files
    _ = @import("parser.zig");
    _ = @import("scanner.zig");
    _ = @import("schema.zig");
    _ = @import("stringify.zig");
}
