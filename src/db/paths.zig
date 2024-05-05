pub fn unique_path(allocator: std.mem.Allocator, id: []const u8, filenames: *StringHashSet) ![]const u8 {
    var differentiator: ?usize = null;
    while (true) : (differentiator = if (differentiator) |d| d+1 else 2) {
        const path = try safe_path(allocator, id, differentiator);
        const result = try filenames.getOrPut(path);
        if (!result.found_existing) {
            result.key_ptr.* = path;
            return path;
        }
    }
    unreachable;
}

pub fn safe_path(allocator: std.mem.Allocator, id: []const u8, differentiator: ?usize) ![]const u8 {
    var dest = try std.ArrayListUnmanaged(u8).initCapacity(allocator, id.len + 3);
    defer dest.deinit(allocator);

    var last_was_underscore = false;
    for (id) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9' => {
                dest.appendAssumeCapacity(c | 0x20);
                last_was_underscore = false;
            },
            else => {
                if (!last_was_underscore) {
                    dest.appendAssumeCapacity('_');
                    last_was_underscore = true;
                }
            },
        }
    }

    if (dest.items.len == 0) {
        try dest.append(allocator, '_');
        last_was_underscore = true;
    }

    if (differentiator) |d| {
        if (!last_was_underscore) try dest.append(allocator, '_');
        try dest.writer(allocator).print("{}", .{ d });
    }

    try dest.appendSlice(allocator, ".sx");
    return dest.toOwnedSlice(allocator);
}

pub fn delete_all_except(dir: *std.fs.Dir, files_to_keep: StringHashSet) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and !files_to_keep.contains(entry.name)) {
            try dir.deleteFile(entry.name);
        }
    }
}

pub const StringHashSet = std.StringHashMap(void);

const std = @import("std");
