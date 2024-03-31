var a = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var g: std.heap.GeneralPurposeAllocator(.{}) = .{};

// If the thread pool has been started, use this mutex to
// synchronize access to mutable global state.
pub var mutex: std.Thread.Mutex = .{};

pub fn arena() std.mem.Allocator {
    return a.allocator();
}

pub fn gpa() std.mem.Allocator {
    return g.allocator();
}

pub fn deinit() void {
    std.debug.assert(g.deinit() == .ok);
    a.deinit();
}

const std = @import("std");
