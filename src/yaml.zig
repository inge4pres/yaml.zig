const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export core types
pub const Value = @import("value.zig").Value;
pub const Scanner = @import("scanner.zig").Scanner;
pub const Parser = @import("parser.zig").Parser;

// Main API functions (to be implemented in Phase 4)
pub const Parsed = @import("parser.zig").Parsed;
pub const parseFromSlice = @import("parser.zig").parseFromSlice;
pub const stringify = @import("stringify.zig").stringify;

test {
    // Import all test files
    _ = @import("parser.zig");
    _ = @import("scanner.zig");
    _ = @import("schema.zig");
    _ = @import("stringify.zig");
}
