pub fn parse_data(db: *DB, reader: *sx.Reader) !void {
    const parsed = try reader.require_object(reader.token.allocator, SX_Data, SX_Data.context);

    for (parsed.mfr) |item| {
        const now = std.time.milliTimestamp();

        const mfr: Manufacturer = .{
            .id = try db.intern(item.id),
            .full_name = if (item.full_name) |s| try db.intern(s) else try db.intern(item.id),
            .country = try db.maybe_intern(item.country),
            .website = try db.maybe_intern(item.url),
            .wiki = try db.maybe_intern(item.wiki),
            .notes = try db.maybe_intern(item.notes),
            .created_timestamp_ms = if (item.created) |dto| dto.timestamp_ms() else now,
            .modified_timestamp_ms = if (item.modified) |dto| dto.timestamp_ms() else now,
        };

        const idx: Manufacturer.Index = @enumFromInt(db.mfrs.len);
        try db.mfrs.append(db.container_alloc, mfr);
        try db.mfr_lookup.putNoClobber(db.container_alloc, mfr.id, idx);

        if (item.created == null or item.modified == null) {
            db.mark_dirty(now);
        }
    }
}

pub fn write_data(db: *DB, root: *std.fs.Dir) !void {
    var temp_arena = try Temp_Allocator.init(500 * 1024 * 1024);
    defer temp_arena.deinit();
    {
        temp_arena.reset(.{});

        var filenames = std.StringHashMap(void).init(temp_arena.allocator());
        defer filenames.deinit();
        try filenames.ensureTotalCapacity(@intCast(db.mfrs.len));

        var mfr_path = try root.makeOpenPath("mfr", .{});
        defer mfr_path.close();
        for (0..db.mfrs.len) |i| {
            const data = db.mfrs.get(i);

            var diff: ?usize = null;
            const dest_path = while (true) : (diff = if (diff) |d| d+1 else 2) {
                const path = try safe_path(temp_arena.allocator(), data.id, diff);
                const result = try filenames.getOrPut(path);
                if (!result.found_existing) {
                    result.key_ptr.* = path;
                    break path;
                }
            } else unreachable;

            var af = try mfr_path.atomicFile(dest_path, .{});
            defer af.deinit();

            var sxw = sx.writer(temp_arena.allocator(), af.file.writer().any());
            defer sxw.deinit();

            try sxw.expression("version");
            try sxw.int(1, 10);
            try sxw.close();

            try sxw.expression_expanded("mfr");
            try sxw.object(SX_Manufacturer {
                .id = data.id,
                .full_name = if (std.mem.eql(u8, data.full_name, data.id)) null else data.full_name,
                .additional_names = &.{}, // TODO
                .url = data.website,
                .wiki = data.wiki,
                .country = data.country,
                .notes = data.notes,
                .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
                .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
                .rel = &.{}, // TODO
            }, SX_Manufacturer.context);
            try sxw.close();

            try af.finish();
        }
    }
}

fn safe_path(alloc: std.mem.Allocator, id: []const u8, differentiator: ?usize) ![]const u8 {
    var dest = try std.ArrayListUnmanaged(u8).initCapacity(alloc, id.len + 3);
    defer dest.deinit(alloc);

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
        try dest.append(alloc, '_');
        last_was_underscore = true;
    }

    if (differentiator) |d| {
        if (!last_was_underscore) try dest.append(alloc, '_');
        try dest.writer(alloc).print("{}", .{ d });
    }

    try dest.appendSlice(alloc, ".sx");
    return dest.toOwnedSlice(alloc);
}


const SX_Data = struct {
    mfr: []SX_Manufacturer = &.{},

    pub const context = struct {
        pub const mfr = SX_Manufacturer.context;
    };
};


pub const SX_Manufacturer = struct {
    id: []const u8 = "",
    full_name: ?[]const u8 = null,
    additional_names: []const []const u8 = &.{},
    url: ?[]const u8 = null,
    wiki: ?[]const u8 = null,
    country: ?[]const u8 = null,
    notes: ?[]const u8 = null,
    created: ?Date_Time.With_Offset = null,
    modified: ?Date_Time.With_Offset = null,
    rel: []const Relation = &.{},

    pub const Relation = struct {
        kind: []const u8 = "",
        other: []const u8 = "",
        year: ?i32 = null,
    };

    pub const context = struct {
        pub const inline_fields = &.{ "id", "full_name", "additional_names" };
        pub const created = Date_Time.With_Offset.fmt_sql;
        pub const modified = Date_Time.With_Offset.fmt_sql;

        pub const rel = struct {
            pub const inline_fields = &.{ "kind", "other", "year" };
        };
    };
};



const Manufacturer = @import("Manufacturer.zig");

const DB = @import("../DB.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const Temp_Allocator = @import("Temp_Allocator");
const sx = @import("sx");
const std = @import("std");
