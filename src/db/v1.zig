pub fn parse_data(db: *DB, reader: *sx.Reader) !void {
    const parsed = try reader.require_object(reader.token.allocator, SX_Data, SX_Data.context);
    for (parsed.mfr) |item| try item.read(db);
}

pub fn write_data(db: *DB, root: *std.fs.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var filenames = paths.StringHashSet.init(arena.allocator());

    try write_manufacturers(arena.allocator(), db, root, &filenames);

    db.dirty_timestamp_ms = null;
}

fn write_manufacturers(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.mfrs.len));
    defer filenames.clearRetainingCapacity();

    const dirty_timestamp_ms = db.dirty_timestamp_ms orelse std.time.milliTimestamp();

    var dir = try root.makeOpenPath("mfr", .{ .iterate = true });
    defer dir.close();

    for (0..db.mfrs.len) |i| {
        const data = db.mfrs.get(i);
        const dest_path = try paths.unique_path(allocator, data.id, filenames);

        if (data.modified_timestamp_ms < dirty_timestamp_ms) continue;

        log.info("Writing mfr{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("mfr");
        try sxw.object(SX_Manufacturer.init(db, @enumFromInt(i)), SX_Manufacturer.context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*);
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

    pub fn init(db: *const DB, index: Manufacturer.Index) SX_Manufacturer {
        const data = db.mfrs.get(@intFromEnum(index));
        return .{
            .id = data.id,
            .full_name = if (std.mem.eql(u8, data.full_name, data.id)) null else data.full_name,
            .additional_names = data.additional_names.items,
            .url = data.website,
            .wiki = data.wiki,
            .country = data.country,
            .notes = data.notes,
            .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
            .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
            .rel = &.{}, // TODO
        };
    }

    pub fn read(self: SX_Manufacturer, db: *DB) !void {
        const now = std.time.milliTimestamp();
        const new_full_name = if (self.full_name) |s| s else self.id;

        const gop = try db.mfr_lookup.getOrPut(db.container_alloc, self.id);
        if (gop.found_existing) {
            const idx = gop.value_ptr.*;
            try Manufacturer.set_full_name(db, idx, new_full_name);
            try Manufacturer.add_additional_names(db, idx, self.additional_names, .{ .set_modified_on_added = true });
            if (self.country) |country| try Manufacturer.set_country(db, idx, country);
            if (self.url) |url| try Manufacturer.set_website(db, idx, url);
            if (self.wiki) |wiki| try Manufacturer.set_wiki(db, idx, wiki);
            if (self.notes) |notes| try Manufacturer.set_notes(db, idx, notes);
            if (self.created) |dto| try Manufacturer.set_created_time(db, idx, dto.timestamp_ms());
            if (self.modified) |dto| try Manufacturer.set_modified_time(db, idx, dto.timestamp_ms());
        } else {
            const id = try db.intern(self.id);
            const idx: Manufacturer.Index = @enumFromInt(db.mfrs.len);
            const mfr: Manufacturer = .{
                .id = id,
                .full_name = try db.intern(new_full_name),
                .country = try db.maybe_intern(self.country),
                .website = try db.maybe_intern(self.url),
                .wiki = try db.maybe_intern(self.wiki),
                .notes = try db.maybe_intern(self.notes),
                .created_timestamp_ms = if (self.created) |dto| dto.timestamp_ms() else now,
                .modified_timestamp_ms = if (self.modified) |dto| dto.timestamp_ms() else now,
                .additional_names = .{},
            };
            try db.mfrs.append(db.container_alloc, mfr);
            gop.key_ptr.* = id;
            gop.value_ptr.* = idx;

            if (self.created == null or self.modified == null) {
                db.mark_dirty(now);
            }

            try Manufacturer.add_additional_names(db, idx, self.additional_names, .{ .set_modified_on_ignore = true });
        }
    }
};

const Manufacturer = @import("Manufacturer.zig");

const log = std.log.scoped(.db);

const paths = @import("paths.zig");
const DB = @import("../DB.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const Temp_Allocator = @import("Temp_Allocator");
const sx = @import("sx");
const std = @import("std");
