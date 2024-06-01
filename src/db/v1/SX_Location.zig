id: []const u8 = "",
full_name: ?[]const u8 = null,
parent: ?[]const u8 = null,
child: []const []const u8 = &.{},
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,
notes: ?[]const u8 = null,

const SX_Location = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id", "full_name" };
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, index: Location.Index) !SX_Location {
    const ids = db.locs.items(.id);
    const parents = db.locs.items(.parent);

    var children = std.ArrayList([]const u8).init(temp);
    for (0.., parents) |child_idx, parent_idx| {
        if (parent_idx == index) {
            try children.append(ids[child_idx]);
        }
    }

    const data = db.locs.get(@intFromEnum(index));

    const parent_id = if (data.parent) |parent_idx| ids[@intFromEnum(parent_idx)] else null;
    return .{
        .id = data.id,
        .full_name = data.full_name,
        .parent = parent_id,
        .child = children.items,
        .notes = data.notes,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Location, db: *DB) !void {
    const id = std.mem.trim(u8, self.id, &std.ascii.whitespace);

    if (!DB.is_valid_id(id)) {
        log.warn("Skipping Location {s} (invalid ID)", .{ id });
        return;
    }

    var full_name = self.full_name;
    if (self.full_name) |name| {
        if (std.mem.eql(u8, id, name)) {
            full_name = null;
        }
    }

    const idx = Location.maybe_lookup(db, full_name) orelse try Location.lookup_or_create(db, id);
    const parent_idx = if (self.parent) |parent_id| try Location.lookup_or_create(db, parent_id) else null;

    _ = try Location.set_id(db, idx, id);
    _ = try Location.set_parent(db, idx, parent_idx);
    if (full_name) |name| try Location.set_full_name(db, idx, name);
    if (self.notes) |notes| try Location.set_notes(db, idx, notes);
    if (self.created) |dto| try Location.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Location.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.locs.len));
    defer filenames.clearRetainingCapacity();

    const dirty_timestamp_ms = db.dirty_timestamp_ms orelse std.time.milliTimestamp();

    var dir = try root.makeOpenPath("loc", .{ .iterate = true });
    defer dir.close();

    for (0..db.locs.len, db.locs.items(.id), db.locs.items(.modified_timestamp_ms)) |i, id, modified_ts| {
        const dest_path = try paths.unique_path(allocator, id, filenames);
        
        if (modified_ts < dirty_timestamp_ms) continue;

        log.info("Writing loc{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("loc");
        try sxw.object(try SX_Location.init(allocator, db, @enumFromInt(i)), SX_Location.context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "loc" ++ std.fs.path.sep_str);
}

const log = std.log.scoped(.db);

const Location = @import("../Location.zig");
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
