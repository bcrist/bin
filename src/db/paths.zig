pub fn unique_path(allocator: std.mem.Allocator, id: []const u8, filenames: *StringHashSet) ![]const u8 {
    return unique_path2(allocator, id, "", filenames);
}

pub fn unique_path2(allocator: std.mem.Allocator, id1: []const u8, id2: []const u8, filenames: *StringHashSet) ![]const u8 {
    var differentiator: ?usize = null;
    while (true) : (differentiator = if (differentiator) |d| d+1 else 2) {
        var temp: [160]u8 = undefined;
        const temp_path = safe_path(&temp, id1, id2, differentiator);
        const result = try filenames.getOrPut(temp_path);
        if (!result.found_existing) {
            const allocated_path = try allocator.dupe(u8, temp_path);
            result.key_ptr.* = allocated_path;
            log.debug("using filename {s} for {s} {s}", .{ allocated_path, id1, id2 });
            return allocated_path;
        }
    }
    unreachable;
}

fn safe_path(buf: []u8, id1: []const u8, id2: []const u8, differentiator: ?usize) []const u8 {
    const reserved = 32;
    std.debug.assert(buf.len > reserved);

    const sep: []const u8 = if (id1.len > 0 and id2.len > 0) "_" else "";

    var start: usize = 0;

    {
        const temp = buf[0 .. buf.len - reserved];
        const encoded_id1 = append_safe_path(id1, temp[start..], false);
        start += encoded_id1.len;
        const encoded_sep = append_safe_path(sep, temp[start..], start > 0 and temp[start - 1] == '_');
        start += encoded_sep.len;
        const encoded_id2 = append_safe_path(id2, temp[start..], start > 0 and temp[start - 1] == '_');
        start += encoded_id2.len;
    }

    if (differentiator) |d| {
        if (start > 0 and buf[start - 1] != '_') {
            buf[start] = '_';
            start += 1;
        }
        const suffix = std.fmt.bufPrint(buf[start..], "{}", .{ d }) catch unreachable;
        start += suffix.len;
    }

    const end = start + 3;
    @memcpy(buf[start..end], ".sx");

    return buf[0..end];
}

fn append_safe_path(id: []const u8, buf: []u8, prev_was_underscore: bool) []const u8 {
    var last_was_underscore = prev_was_underscore;
    var i: usize = 0;
    for (id) |c| {
        if (i == buf.len) break;
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9' => {
                buf[i] = c;
                i += 1;
                last_was_underscore = false;
            },
            else => {
                if (!last_was_underscore) {
                    buf[i] = '_';
                    i += 1;
                    last_was_underscore = true;
                }
            },
        }
    }
    return buf[0..i];
}

pub fn delete_all_except(dir: *std.fs.Dir, files_to_keep: StringHashSet, prefix: []const u8) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and !files_to_keep.contains(entry.name)) {
            log.info("Deleting {s}{s}", .{ prefix, entry.name });
            try dir.deleteFile(entry.name);
        }
    }
}

pub const StringHashSet = std.StringHashMap(void);

const log = std.log.scoped(.db);

const std = @import("std");
