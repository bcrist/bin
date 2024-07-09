id: []const u8 = "",
dist: ?[]const u8 = null,
po: ?[]const u8 = null,
prj: []const []const u8 = &.{},
notes: ?[]const u8 = null,
total: ?[]const u8 = null,
preparing: ?Date_Time.With_Offset = null,
waiting: ?Date_Time.With_Offset = null,
arrived: ?Date_Time.With_Offset = null,
completed: ?Date_Time.With_Offset = null,
cancelled: ?Date_Time.With_Offset = null,
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,
item: []const SX_Order_Item = &.{},

const SX_Order = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id" };
    pub const preparing = Date_Time.With_Offset.fmt_sql;
    pub const waiting = Date_Time.With_Offset.fmt_sql;
    pub const arrived = Date_Time.With_Offset.fmt_sql;
    pub const completed = Date_Time.With_Offset.fmt_sql;
    pub const cancelled = Date_Time.With_Offset.fmt_sql;
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
    pub const item = SX_Order_Item.context;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Order.Index) !SX_Order {
    var prj_order_links = std.ArrayList(Order.Project_Link).init(temp);
    for (db.prj_order_links.keys()) |link| {
        if (link.order == idx) {
            try prj_order_links.append(link);
        }
    }
    std.sort.block(Order.Project_Link, prj_order_links.items, {}, Order.Project_Link.order_less_than);

    const projects = try temp.alloc([]const u8, prj_order_links.items.len);
    const project_ids = db.prjs.items(.id);
    for (projects, prj_order_links.items) |*project_id, link| {
        project_id.* = project_ids[link.prj.raw()];
    }

    var order_items = std.ArrayList(SX_Order_Item).init(temp);
    for (0.., db.order_items.items(.order)) |i, item_order_idx| {
        if (item_order_idx == idx) {
            try order_items.append(try SX_Order_Item.init(temp, db, Order_Item.Index.init(i)));
        }
    }
    std.sort.block(SX_Order_Item, order_items.items, {}, SX_Order_Item.less_than);

    const data = Order.get(db, idx);
    const total_cost_str = if (data.total_cost_hundreths) |cost| try costs.hundreths_to_decimal(temp, cost) else null;

    return .{
        .id = data.id,
        .dist = if (data.dist) |dist_idx| Distributor.get_id(db, dist_idx) else null,
        .po = data.po,
        .prj = projects,
        .notes = data.notes,
        .total = total_cost_str,
        .preparing = if (data.preparing_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .waiting = if (data.waiting_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .arrived = if (data.arrived_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .completed = if (data.completed_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .cancelled = if (data.cancelled_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
        .item = order_items.items,
    };
}

pub fn read(self: SX_Order, db: *DB) !void {
    const id = std.mem.trim(u8, self.id, &std.ascii.whitespace);

    if (db.order_lookup.get(id)) |idx| {
        try Order_Item.delete_all_for_order(db, idx);
    }

    const idx = try Order.lookup_or_create(db, id);

    try Order.set_id(db, idx, id);
    if (self.dist) |dist_id| {
        try Order.set_dist(db, idx, try Distributor.lookup_or_create(db, dist_id));
    }
    if (self.po) |po| try Order.set_po(db, idx, po);
    if (self.notes) |notes| try Order.set_notes(db, idx, notes);
    if (self.total) |cost_str| try Order.set_total_cost_hundreths(db, idx, try costs.decimal_to_hundreths(cost_str));
    if (self.preparing) |dto| try Order.set_preparing_time(db, idx, dto.timestamp_ms());
    if (self.waiting) |dto| try Order.set_waiting_time(db, idx, dto.timestamp_ms());
    if (self.arrived) |dto| try Order.set_arrived_time(db, idx, dto.timestamp_ms());
    if (self.completed) |dto| try Order.set_completed_time(db, idx, dto.timestamp_ms());
    if (self.cancelled) |dto| try Order.set_cancelled_time(db, idx, dto.timestamp_ms());
    if (self.created) |dto| try Order.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Order.set_modified_time(db, idx, dto.timestamp_ms());

    var project_ordering: u16 = 0;
    for (self.prj) |project_id| {
        const link_idx = try Order.Project_Link.lookup_or_create(db, .{
            .order = idx,
            .prj = try Project.lookup_or_create(db, project_id),
        });
        try Order.Project_Link.set_order_ordering(db, link_idx, project_ordering);
        project_ordering += 1;
    }

    for (0.., self.item) |i, sx_item| try sx_item.read(db, idx, i);
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.orders.len));
    defer filenames.clearRetainingCapacity();

    var dir = try root.makeOpenPath("o", .{ .iterate = true });
    defer dir.close();

    for (0.., db.orders.items(.id)) |i, id| {
        if (id.len == 0) continue;

        const dest_path = try paths.unique_path(allocator, id, filenames);
        const idx = Order.Index.init(i);

        if (!db.dirty_set.contains(idx.any())) continue;

        log.info("Writing o{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("order");
        try sxw.object(try init(allocator, db, idx), context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "o" ++ std.fs.path.sep_str);
}

const log = std.log.scoped(.db);

const SX_Order_Item = @import("SX_Order_Item.zig");
const Order = DB.Order;
const Order_Item = DB.Order_Item;
const Project = DB.Project;
const Distributor = DB.Distributor;
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const costs = @import("../../costs.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
