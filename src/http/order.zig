pub const list = @import("order/list.zig");
pub const add = @import("order/add.zig");
pub const edit = @import("order/edit.zig");
pub const reorder_prjs = @import("order/reorder_prjs.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_order_name = try req.get_path_param("o");
    const idx = Order.maybe_lookup(db, requested_order_name) orelse {
        try list.get(session, req, db);
        return;
    };
    const order = Order.get(db, idx);

    if (!std.mem.eql(u8, requested_order_name.?, order.id)) {
        try req.redirect(try http.tprint("/o:{}", .{ http.fmtForUrl(order.id) }), .moved_permanently);
        return;
    }

    if (try req.has_query_param("edit")) {
        try Session.redirect_if_missing(req, session);
        var txn = try Transaction.init_idx(db, idx, tz);
        try txn.render_results(session, req, .{
            .target = .edit,
            .rnd = null,
        });
        return;
    }

    const project_links = try get_sorted_project_links(db, idx);
    const projects = try http.temp().alloc([]const u8, project_links.items.len);
    for (projects, project_links.items) |*project_id, link| {
        project_id.* = Project.get_id(db, link.prj);
    }

    const item_info = try get_sorted_item_info(db, idx);

    const dist_id = if (order.dist) |dist_idx| Distributor.get_id(db, dist_idx) else null;

    const DTO = tempora.Date_Time.With_Offset;
    const preparing_dto = if (order.preparing_timestamp_ms) |ts| DTO.from_timestamp_ms(ts, tz) else null;
    const waiting_dto = if (order.waiting_timestamp_ms) |ts| DTO.from_timestamp_ms(ts, tz) else null;
    const arrived_dto = if (order.arrived_timestamp_ms) |ts| DTO.from_timestamp_ms(ts, tz) else null;
    const completed_dto = if (order.completed_timestamp_ms) |ts| DTO.from_timestamp_ms(ts, tz) else null;
    const cancelled_dto = if (order.cancelled_timestamp_ms) |ts| DTO.from_timestamp_ms(ts, tz) else null;
    const created_dto = DTO.from_timestamp_ms(order.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(order.modified_timestamp_ms, tz);

    const Context = struct {
        pub const preparing_time = DTO.fmt_sql;
        pub const waiting_time = DTO.fmt_sql;
        pub const arrived_time = DTO.fmt_sql;
        pub const completed_time = DTO.fmt_sql;
        pub const cancelled_time = DTO.fmt_sql;
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
        pub const items = struct {
            pub const qty = "d:0>1";
        };
    };

    try req.render("order/info.zk", .{
        .session = session,
        .title = order.id,
        .obj = order,
        .dist_id = dist_id,
        .status = order.get_status().display(),
        .items = item_info.items,
        .preparing_time = preparing_dto,
        .waiting_time = waiting_dto,
        .arrived_time = arrived_dto,
        .completed_time = completed_dto,
        .cancelled_time = cancelled_dto,
        .projects = projects,
        .created = created_dto,
        .modified = modified_dto,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_order_name = try req.get_path_param("o");
    const idx = Order.maybe_lookup(db, requested_order_name) orelse return;

    try Order.delete(db, idx);

    try req.redirect("/o", .see_other);
}

pub fn get_sorted_project_links(db: *const DB, idx: Order.Index) !std.ArrayList(Order.Project_Link) {
    var links = std.ArrayList(Order.Project_Link).init(http.temp());
    for (db.prj_order_links.keys()) |link| {
        if (link.order == idx) {
            try links.append(link);
        }
    }
    std.sort.block(Order.Project_Link, links.items, {}, Order.Project_Link.order_less_than);
    return links;
}

pub fn get_sorted_item_info(db: *const DB, idx: Order.Index) !std.ArrayList(Item_Info) {
    var items = std.ArrayList(Item_Info).init(http.temp());
    const s = db.order_items.slice();
    const orderings = s.items(.ordering);
    const parts = s.items(.part);
    const qtys = s.items(.qty);
    const qty_uncertainties = s.items(.qty_uncertainty);
    const locs = s.items(.loc);
    const cost_each_hundreths = s.items(.cost_each_hundreths);
    const cost_total_hundreths = s.items(.cost_total_hundreths);
    const notes = s.items(.notes);

    const loc_ids = db.locs.items(.id);
    const mfr_ids = db.mfrs.items(.id);
    const part_ids = db.parts.items(.id);
    const part_mfrs = db.parts.items(.mfr);

    for (0.., s.items(.order)) |i, order_idx| {
        if (order_idx != idx) continue;

        const maybe_qty = qtys[i];
        const qty_uncertainty = qty_uncertainties[i];

        var each = if (cost_each_hundreths[i]) |hundreths| try costs.hundreths_to_decimal(http.temp(), hundreths) else null;
        var subtotal = if (cost_total_hundreths[i]) |hundreths| try costs.hundreths_to_decimal(http.temp(), hundreths) else null;

        if (maybe_qty) |qty| {
            if (qty_uncertainty != .approx) {
                if (each == null and subtotal != null) {
                    const amount = @divTrunc(cost_total_hundreths[i].? + @divTrunc(qty, 2), qty);
                    each = try costs.hundreths_to_decimal(http.temp(), amount);
                } else if (subtotal == null and each != null) {
                    const amount = cost_each_hundreths[i].? * qty;
                    subtotal = try costs.hundreths_to_decimal(http.temp(), amount);
                }
            }
        }

        try items.append(.{
            .ordering = orderings[i],
            .part = if (parts[i]) |part_idx| .{
                .mfr_id = if (part_mfrs[part_idx.raw()]) |mfr_idx| mfr_ids[mfr_idx.raw()] else null,
                .part_id = part_ids[part_idx.raw()],
            } else null,
            .qty = maybe_qty,
            .qty_uncertainty = qty_uncertainty,
            .loc_id = if (locs[i]) |loc_idx| loc_ids[loc_idx.raw()] else null,
            .cost_each = each,
            .cost_subtotal = subtotal,
            .notes = notes[i],
        });
    }
    std.sort.block(Item_Info, items.items, {}, Item_Info.less_than);
    return items;
}

pub const Item_Info = struct {
    ordering: u32,
    part: ?Part_Info,
    qty: ?i32,
    qty_uncertainty: ?Order_Item.Quantity_Uncertainty,
    loc_id: ?[]const u8,
    cost_each: ?[]const u8,
    cost_subtotal: ?[]const u8,
    notes: ?[]const u8,

    pub fn less_than(_: void, a: Item_Info, b: Item_Info) bool {
        return a.ordering < b.ordering;
    }
};

const log = std.log.scoped(.@"http.order");

const Part_Info = @import("part.zig").Part_Info;
const Transaction = @import("order/Transaction.zig");
const Location = DB.Location;
const Order_Item = DB.Order_Item;
const Order = DB.Order;
const Project = DB.Project;
const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const slimselect = @import("slimselect.zig");
const costs = @import("../costs.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
