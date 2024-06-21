id: []const u8 = "",
full_name: ?[]const u8 = null,
parent: ?[]const u8 = null,
child: []const []const u8 = &.{},
mfr: ?[]const u8 = null,
pkg: ?[]const u8 = null,
notes: ?[]const u8 = null,
dist_pn: []const Distributor_Part_Number = &.{},
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const Distributor_Part_Number = struct {
    dist: []const u8 = "",
    pn: []const u8 = "",
};

const SX_Part = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id", "full_name" };
    pub const dist_pn = struct {
        pub const inline_fields = &.{ "dist", "pn" };
    };
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Part.Index) !SX_Part {
    var children = std.ArrayList([]const u8).init(temp);
    const ids = db.parts.items(.id);
    for (0.., db.parts.items(.parent)) |child_i, parent_idx| {
        if (parent_idx == idx) {
            try children.append(ids[child_i]);
        }
    }

    const data = Part.get(db, idx);

    const dist_ids = db.dists.items(.id);
    const dist_pns = try temp.alloc(Distributor_Part_Number, data.dist_pns.items.len);
    for (data.dist_pns.items, dist_pns) |src, *dest| {
        dest.* = .{
            .dist = dist_ids[@intFromEnum(src.dist)],
            .pn = src.pn,
        };
    }

    const parent_id = if (data.parent) |parent_idx| Part.get_id(db, parent_idx) else null;
    const mfr_id = if (data.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null;
    const pkg_id = if (data.pkg) |pkg_idx| Package.get_id(db, pkg_idx) else null;
    return .{
        .id = data.id,
        .full_name = data.full_name,
        .parent = parent_id,
        .child = children.items,
        .mfr = mfr_id,
        .pkg = pkg_id,
        .notes = data.notes,
        .dist_pn = dist_pns,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Part, db: *DB) !void {
    const id = std.mem.trim(u8, self.id, &std.ascii.whitespace);

    if (!DB.is_valid_id(id)) {
        log.warn("Skipping Part {s} (invalid ID)", .{ id });
        return;
    }

    var full_name = self.full_name;
    if (self.full_name) |name| {
        if (std.mem.eql(u8, id, name)) {
            full_name = null;
        }
    }

    const idx = Part.maybe_lookup(db, full_name)
        orelse try Part.lookup_or_create(db, id);

    _ = try Part.set_id(db, idx, id);

    if (self.parent) |parent_id| {
        const parent_idx = try Part.lookup_or_create(db, parent_id);
        _ = try Part.set_parent(db, idx, parent_idx);
    }

    if (self.mfr) |mfr_id| {
        const mfr_idx = try Manufacturer.lookup_or_create(db, mfr_id);
        _ = try Part.set_mfr(db, idx, mfr_idx);
    }

    if (self.pkg) |pkg_id| {
        const pkg_idx = try Package.lookup_or_create(db, pkg_id);
        _ = try Part.set_pkg(db, idx, pkg_idx);
    }

    for (self.dist_pn) |pn| {
        try Part.add_dist_pn(db, idx, .{
            .dist = try Distributor.lookup_or_create(db, pn.dist),
            .pn = pn.pn,
        });
    }

    if (full_name) |name| try Part.set_full_name(db, idx, name);
    if (self.notes) |notes| try Part.set_notes(db, idx, notes);

    if (self.created) |dto| try Part.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Part.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.parts.len));
    defer filenames.clearRetainingCapacity();

    const dirty_timestamp_ms = db.dirty_timestamp_ms orelse std.time.milliTimestamp();

    var dir = try root.makeOpenPath("p", .{ .iterate = true });
    defer dir.close();

    for (0..db.parts.len, db.parts.items(.id), db.parts.items(.modified_timestamp_ms)) |i, id, modified_ts| {
        const dest_path = try paths.unique_path(allocator, id, filenames);
        
        if (modified_ts < dirty_timestamp_ms) continue;

        const DTO = Date_Time.With_Offset;
        const modified_dto = DTO.from_timestamp_ms(modified_ts, null);
        log.info("Writing p{s}{s} (modified {" ++ DTO.fmt_sql_ms ++ "})", .{ std.fs.path.sep_str, dest_path, modified_dto });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("part");
        try sxw.object(try SX_Part.init(allocator, db, @enumFromInt(i)), SX_Part.context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "p" ++ std.fs.path.sep_str);
}

const log = std.log.scoped(.db);

const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const Package = DB.Package;
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
