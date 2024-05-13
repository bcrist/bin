
pub fn lexicographic(data: [][]const u8) void {
    std.sort.block([]const u8, data, {}, lexicographic_less_than);
}

pub fn lexicographic_less_than(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

const std = @import("std");
