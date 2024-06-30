id: SX_ID_With_Manufacturer = .{},
parent: ?SX_ID_With_Manufacturer = null,
child: []const SX_ID_With_Manufacturer = &.{},
pkg: ?SX_ID_With_Manufacturer = null,
notes: ?[]const u8 = null,
dist_pn: []const Distributor_Part_Number = &.{},
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const Distributor_Part_Number = struct {
    dist: []const u8 = "",
    pn: []const u8 = "",

    pub const context = struct {
        pub const inline_fields = &.{ "dist", "pn" };
    };
};

const SX_Part = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id" };
    pub const id = SX_ID_With_Manufacturer.context;
    pub const parent = SX_ID_With_Manufacturer.context;
    pub const child = SX_ID_With_Manufacturer.context;
    pub const pkg = SX_ID_With_Manufacturer.context;
    pub const dist_pn = Distributor_Part_Number.context;
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Part.Index) !SX_Part {
    const ids = db.parts.items(.id);
    const mfrs = db.parts.items(.mfr);
    const mfr_ids = db.mfrs.items(.id);
    const dist_ids = db.dists.items(.id);
    
    var children = std.ArrayList(SX_ID_With_Manufacturer).init(temp);
    for (0.., db.parts.items(.parent)) |child_i, parent_idx| {
        if (parent_idx == idx) {
            try children.append(.{
                .mfr = if (mfrs[child_i]) |mfr_idx| mfr_ids[mfr_idx.raw()] else "_",
                .id = ids[child_i],
            });
        }
    }

    const data = Part.get(db, idx);

    const dist_pns = try temp.alloc(Distributor_Part_Number, data.dist_pns.items.len);
    for (data.dist_pns.items, dist_pns) |src, *dest| {
        dest.* = .{
            .dist = dist_ids[src.dist.raw()],
            .pn = src.pn,
        };
    }

    const id: SX_ID_With_Manufacturer = .{
        .mfr = if (data.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "_",
        .id = data.id,
    };

    const parent: ?SX_ID_With_Manufacturer = if (data.parent) |parent_idx| .{
        .mfr = if (Part.get_mfr(db, parent_idx)) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "_",
        .id = Part.get_id(db, parent_idx),
    } else null;

    const pkg: ?SX_ID_With_Manufacturer = if (data.pkg) |pkg_idx| .{
        .mfr = if (Package.get_mfr(db, pkg_idx)) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "_",
        .id = Package.get_id(db, pkg_idx),
    } else null;

    return .{
        .id = id,
        .parent = parent,
        .child = children.items,
        .pkg = pkg,
        .notes = data.notes,
        .dist_pn = dist_pns,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Part, db: *DB) !void {
    const id = std.mem.trim(u8, self.id.id, &std.ascii.whitespace);

    const mfr_idx = try self.id.get_mfr_idx(db);
    const idx = try Part.lookup_or_create(db, mfr_idx, id);

    if (self.parent) |parent| {
        const parent_mfr_idx = try parent.get_mfr_idx(db);
        const parent_idx = try Part.lookup_or_create(db, parent_mfr_idx, parent.id);
        try Part.set_parent(db, idx, parent_idx);
    }

    if (self.pkg) |pkg| {
        const pkg_mfr_idx = try pkg.get_mfr_idx(db);
        const pkg_idx = try Package.lookup_or_create(db, pkg_mfr_idx, pkg.id);
        try Part.set_pkg(db, idx, pkg_idx);
    }

    for (self.dist_pn) |pn| {
        try Part.add_dist_pn(db, idx, .{
            .dist = try Distributor.lookup_or_create(db, pn.dist),
            .pn = pn.pn,
        });
    }

    if (self.notes) |notes| try Part.set_notes(db, idx, notes);

    if (self.created) |dto| try Part.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Part.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.parts.len));
    defer filenames.clearRetainingCapacity();

    var dir = try root.makeOpenPath("p", .{ .iterate = true });
    defer dir.close();

    const parents = db.parts.items(.parent);

    // Make sure any dirty child parts also mark their root parts dirty:
    for (0.., parents) |i, maybe_parent_idx| {
        var root_idx = Part.Index.init(i);
        if (!db.dirty_set.contains(root_idx.any())) continue;

        var maybe_root_parent_idx = maybe_parent_idx;
        while (maybe_root_parent_idx) |root_parent_idx| {
            root_idx = root_parent_idx;
            maybe_root_parent_idx = parents[root_idx.raw()];
        }

        try db.mark_dirty(root_idx);
    }

    for (0.., db.parts.items(.id), parents, db.parts.items(.mfr)) |i, id, maybe_parent_idx, maybe_mfr_idx| {
        if (maybe_parent_idx != null) continue; // only write files for root parts

        const mfr_id = if (maybe_mfr_idx) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "";
        const dest_path = try paths.unique_path2(allocator, mfr_id, id, filenames);
        const idx = Part.Index.init(i);
        
        if (!db.dirty_set.contains(idx.any())) continue;

        log.info("Writing p{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try write_with_children(allocator, db, &sxw, idx);

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "p" ++ std.fs.path.sep_str);
}

pub fn write_with_children(allocator: std.mem.Allocator, db: *DB, sxw: *sx.Writer, idx: Part.Index) !void {
    try sxw.expression_expanded("part");
    try sxw.object(try SX_Part.init(allocator, db, idx), SX_Part.context);
    try sxw.close();

    for (0.., db.parts.items(.parent)) |i, maybe_parent_idx| {
        if (maybe_parent_idx == idx) {
            try write_with_children(allocator, db, sxw, Part.Index.init(i));
        }
    }
}

const log = std.log.scoped(.db);

const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const Package = DB.Package;
const DB = @import("../../DB.zig");
const SX_ID_With_Manufacturer = @import("SX_ID_With_Manufacturer.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
