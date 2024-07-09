var a = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var g: std.heap.GeneralPurposeAllocator(.{}) = .{};

// If the thread pool has been started, use this mutex to
// synchronize access to mutable global state.
pub var mutex: std.Thread.Mutex = .{};
pub var check_for_leaks_before_deinit: bool = false;

pub fn arena() std.mem.Allocator {
    return a.allocator();
}

pub fn gpa() std.mem.Allocator {
    return g.allocator();
}

pub fn deinit() void {
    a.deinit();
    if (check_for_leaks_before_deinit) std.debug.assert(g.deinit() == .ok);
}

const std = @import("std");
