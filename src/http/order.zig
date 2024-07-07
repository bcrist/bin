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
    };

    try req.render("order/info.zk", .{
        .session = session,
        .title = order.id,
        .obj = order,
        .dist_id = dist_id,
        .status = order.get_status().display(),
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

const log = std.log.scoped(.@"http.order");

const Transaction = @import("order/Transaction.zig");
const Order = DB.Order;
const Project = DB.Project;
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const slimselect = @import("slimselect.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
