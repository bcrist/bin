id: []const u8 = "",
full_name: ?[]const u8 = null,
status: ?Project.Status = .active,
status_changed: ?Date_Time.With_Offset = null,
parent: ?[]const u8 = null,
child: []const []const u8 = &.{},
order: []const []const u8 = &.{},
website: ?[]const u8 = null,
source_control: ?[]const u8 = null,
notes: ?[]const u8 = null,
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const SX_Project = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id", "full_name", "status", "status_changed" };
    pub const status_changed = Date_Time.With_Offset.fmt_sql;
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Project.Index) !SX_Project {
    var children = std.ArrayList([]const u8).init(temp);
    const ids = db.prjs.items(.id);
    for (0.., db.prjs.items(.parent)) |child_i, parent_idx| {
        if (parent_idx == idx) {
            try children.append(ids[child_i]);
        }
    }

    var prj_order_links = std.ArrayList(Order.Project_Link).init(temp);
    for (db.prj_order_links.keys()) |link| {
        if (link.prj == idx) {
            try prj_order_links.append(link);
        }
    }
    std.sort.block(Order.Project_Link, prj_order_links.items, {}, Order.Project_Link.prj_less_than);

    const orders = try temp.alloc([]const u8, prj_order_links.items.len);
    const order_ids = db.orders.items(.id);
    for (orders, prj_order_links.items) |*order, link| {
        order.* = order_ids[link.order.raw()];
    }

    const data = Project.get(db, idx);
    var full_name = data.full_name;
    if (full_name == null) {
        full_name = data.id;
    }

    const parent_id = if (data.parent) |parent_idx| Project.get_id(db, parent_idx) else null;
    return .{
        .id = data.id,
        .full_name = full_name,
        .status = data.status,
        .status_changed = Date_Time.With_Offset.from_timestamp_ms(data.status_change_timestamp_ms, null),
        .parent = parent_id,
        .child = children.items,
        .order = orders,
        .website = data.website,
        .source_control = data.source_control,
        .notes = data.notes,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Project, db: *DB) !void {
    const id = std.mem.trim(u8, self.id, &std.ascii.whitespace);

    var full_name = self.full_name;
    if (self.full_name) |name| {
        if (std.mem.eql(u8, id, name)) {
            full_name = null;
        }
    }

    const idx = Project.maybe_lookup(db, full_name) orelse try Project.lookup_or_create(db, id);
    const parent_idx = if (self.parent) |parent_id| try Project.lookup_or_create(db, parent_id) else null;

    try Project.set_id(db, idx, id);
    try Project.set_parent(db, idx, parent_idx);
    if (full_name) |name| try Project.set_full_name(db, idx, name);
    if (self.status) |status| try Project.set_status(db, idx, status);
    if (self.status_changed) |dto| try Project.set_status_change_time(db, idx, dto.timestamp_ms());
    if (self.website) |url| try Project.set_website(db, idx, url);
    if (self.source_control) |url| try Project.set_source_control(db, idx, url);
    if (self.notes) |notes| try Project.set_notes(db, idx, notes);
    if (self.created) |dto| try Project.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Project.set_modified_time(db, idx, dto.timestamp_ms());

    var order_ordering: u16 = 0;
    for (self.order) |order_id| {
        const link_idx = try Order.Project_Link.lookup_or_create(db, .{
            .order = try Order.lookup_or_create(db, order_id),
            .prj = idx,
        });
        try Order.Project_Link.set_prj_ordering(db, link_idx, order_ordering);
        order_ordering += 1;
    }
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.prjs.len));
    defer filenames.clearRetainingCapacity();

    var dir = try root.makeOpenPath("prj", .{ .iterate = true });
    defer dir.close();

    // Make sure any dirty child projects also mark their root projects dirty:
    const parents = db.prjs.items(.parent);
    for (0.., parents) |i, maybe_parent_idx| {
        var root_idx = Project.Index.init(i);
        if (!db.dirty_set.contains(root_idx.any())) continue;

        var maybe_root_parent_idx = maybe_parent_idx;
        while (maybe_root_parent_idx) |root_parent_idx| {
            root_idx = root_parent_idx;
            maybe_root_parent_idx = parents[root_idx.raw()];
        }

        try db.mark_dirty(root_idx);
    }

    for (0.., db.prjs.items(.id), db.prjs.items(.parent)) |i, id, maybe_parent_idx| {
        if (maybe_parent_idx != null) continue; // only write files for root projects

        const dest_path = try paths.unique_path(allocator, id, filenames);
        const idx = Project.Index.init(i);
        
        if (!db.dirty_set.contains(idx.any())) continue;

        log.info("Writing prj{s}{s}", .{ std.fs.path.sep_str, dest_path });

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

    try paths.delete_all_except(&dir, filenames.*, "prj" ++ std.fs.path.sep_str);
}

pub fn write_with_children(allocator: std.mem.Allocator, db: *DB, sxw: *sx.Writer, idx: Project.Index) !void {
    try sxw.expression_expanded("prj");
    try sxw.object(try SX_Project.init(allocator, db, idx), SX_Project.context);
    try sxw.close();

    for (0.., db.prjs.items(.parent)) |i, maybe_parent_idx| {
        if (maybe_parent_idx == idx) {
            try write_with_children(allocator, db, sxw, Project.Index.init(i));
        }
    }
}

const log = std.log.scoped(.db);

const Project = DB.Project;
const Order = DB.Order;
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
