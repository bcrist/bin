id: SX_ID_With_Manufacturer = .{},
full_name: ?[]const u8 = null,
additional_names: []const []const u8 = &.{},
parent: ?SX_ID_With_Manufacturer = null,
child: []const SX_ID_With_Manufacturer = &.{},
notes: ?[]const u8 = null,
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const SX_Package = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id", "full_name", "additional_names" };
    pub const id = SX_ID_With_Manufacturer.context;
    pub const parent = SX_ID_With_Manufacturer.context;
    pub const child = SX_ID_With_Manufacturer.context;
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Package.Index) !SX_Package {
    const ids = db.pkgs.items(.id);
    const mfrs = db.pkgs.items(.mfr);
    const mfr_ids = db.mfrs.items(.id);

    var children = std.ArrayList(SX_ID_With_Manufacturer).init(temp);
    for (0.., db.pkgs.items(.parent)) |child_i, parent_idx| {
        if (parent_idx == idx) {
            try children.append(.{
                .mfr = if (mfrs[child_i]) |mfr_idx| mfr_ids[mfr_idx.raw()] else "_",
                .id = ids[child_i],
            });
        }
    }

    const data = Package.get(db, idx);

    const id: SX_ID_With_Manufacturer = .{
        .mfr = if (data.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "_",
        .id = data.id,
    };

    const parent: ?SX_ID_With_Manufacturer = if (data.parent) |parent_idx| .{
        .mfr = if (Package.get_mfr(db, parent_idx)) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "_",
        .id = Package.get_id(db, parent_idx),
    } else null;

    return .{
        .id = id,
        .full_name = data.full_name,
        .additional_names = data.additional_names.items,
        .parent = parent,
        .child = children.items,
        .notes = data.notes,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Package, db: *DB) !void {
    const id = std.mem.trim(u8, self.id.id, &std.ascii.whitespace);

    var full_name = self.full_name;
    if (self.full_name) |name| {
        if (std.mem.eql(u8, id, name)) {
            full_name = null;
        }
    }

    const mfr_idx = try self.id.get_mfr_idx(db);
    const idx = Package.maybe_lookup(db, mfr_idx, full_name)
        orelse Package.lookup_multiple(db, mfr_idx, self.additional_names)
        orelse try Package.lookup_or_create(db, mfr_idx, id);

    try Package.set_id(db, idx, mfr_idx, id);

    if (self.parent) |parent| {
        const parent_mfr_idx = try parent.get_mfr_idx(db);
        const parent_idx = try Package.lookup_or_create(db, parent_mfr_idx, parent.id);
        try Package.set_parent(db, idx, parent_idx);
    }

    if (full_name) |name| try Package.set_full_name(db, idx, name);
    if (self.notes) |notes| try Package.set_notes(db, idx, notes);
    try Package.add_additional_names(db, idx, self.additional_names);

    if (self.created) |dto| try Package.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Package.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.pkgs.len));
    defer filenames.clearRetainingCapacity();

    var dir = try root.makeOpenPath("pkg", .{ .iterate = true });
    defer dir.close();
    
    // Make sure any dirty child packages also mark their root packages dirty:
    const parents = db.pkgs.items(.parent);
    for (0.., parents) |i, maybe_parent_idx| {
        var root_idx = Package.Index.init(i);
        if (!db.dirty_set.contains(root_idx.any())) continue;

        var maybe_root_parent_idx = maybe_parent_idx;
        while (maybe_root_parent_idx) |root_parent_idx| {
            root_idx = root_parent_idx;
            maybe_root_parent_idx = parents[root_idx.raw()];
        }

        try db.mark_dirty(root_idx);
    }

    for (0.., db.pkgs.items(.id), parents, db.pkgs.items(.mfr)) |i, id, maybe_parent_idx, maybe_mfr_idx| {
        if (id.len == 0) continue;
        if (maybe_parent_idx != null) continue; // only write files for root packages

        const mfr_id = if (maybe_mfr_idx) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else "";
        const dest_path = try paths.unique_path2(allocator, mfr_id, id, filenames);
        const idx = Package.Index.init(i);
        
        if (!db.dirty_set.contains(idx.any())) continue;

        log.info("Writing pkg{s}{s}", .{ std.fs.path.sep_str, dest_path });

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

    try paths.delete_all_except(&dir, filenames.*, "pkg" ++ std.fs.path.sep_str);
}

pub fn write_with_children(allocator: std.mem.Allocator, db: *DB, sxw: *sx.Writer, idx: Package.Index) !void {
    try sxw.expression_expanded("pkg");
    try sxw.object(try SX_Package.init(allocator, db, idx), SX_Package.context);
    try sxw.close();

    for (0.., db.pkgs.items(.parent)) |i, maybe_parent_idx| {
        if (maybe_parent_idx == idx) {
            try write_with_children(allocator, db, sxw, Package.Index.init(i));
        }
    }
}

const log = std.log.scoped(.db);

const Package = DB.Package;
const Manufacturer = @import("../Manufacturer.zig");
const DB = @import("../../DB.zig");
const SX_ID_With_Manufacturer = @import("SX_ID_With_Manufacturer.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
