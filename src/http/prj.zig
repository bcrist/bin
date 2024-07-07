pub const list = @import("prj/list.zig");
pub const add = @import("prj/add.zig");
pub const edit = @import("prj/edit.zig");
pub const reorder_orders = @import("prj/reorder_orders.zig");

pub const statuses = struct {
    pub fn get(req: *http.Request) !void {
        try slimselect.respond_with_enum_options(req, Project.Status, .{
            .display_fn = Project.Status.display,
        });
    }
};

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_prj_name = try req.get_path_param("prj");
    const idx = Project.maybe_lookup(db, requested_prj_name) orelse {
        try list.get(session, req, db);
        return;
    };
    const prj = Project.get(db, idx);

    if (!std.mem.eql(u8, requested_prj_name.?, prj.id)) {
        try req.redirect(try http.tprint("/prj:{}", .{ http.fmtForUrl(prj.id) }), .moved_permanently);
        return;
    }

    if (try req.has_query_param("edit")) {
        try Session.redirect_if_missing(req, session);
        var txn = try Transaction.init_idx(db, idx);
        try txn.render_results(session, req, .{
            .target = .edit,
            .rnd = null,
        });
        return;
    }

    const parent_id = if (prj.parent) |parent_idx| Project.get_id(db, parent_idx) else null;

    var children = std.ArrayList([]const u8).init(http.temp());
    for (db.prjs.items(.parent), db.prjs.items(.id)) |parent_idx, id| {
        if (parent_idx == idx) {
            try children.append(id);
        }
    }
    sort.natural(children.items);

    const order_links = try get_sorted_order_links(db, idx);
    const orders = try http.temp().alloc([]const u8, order_links.items.len);
    for (orders, order_links.items) |*order_id, link| {
        order_id.* = Order.get_id(db, link.order);
    }

    const DTO = tempora.Date_Time.With_Offset;

    const status_changed_dto = DTO.from_timestamp_ms(prj.status_change_timestamp_ms, tz);
    const created_dto = DTO.from_timestamp_ms(prj.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(prj.modified_timestamp_ms, tz);

    const Context = struct {
        pub const status_change_time = DTO.fmt_sql;
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    try req.render("prj/info.zk", .{
        .session = session,
        .title = prj.full_name orelse prj.id,
        .obj = prj,
        .status_str = prj.status.display(),
        .status_change_time = status_changed_dto,
        .parent_id = parent_id,
        .children = children.items,
        .orders = orders,
        .created = created_dto,
        .modified = modified_dto,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_prj_name = try req.get_path_param("prj");
    const idx = Project.maybe_lookup(db, requested_prj_name) orelse return;

    try Project.delete(db, idx, true);

    try req.redirect("/prj", .see_other);
}

pub fn get_sorted_order_links(db: *const DB, idx: Project.Index) !std.ArrayList(Order.Project_Link) {
    var links = std.ArrayList(Order.Project_Link).init(http.temp());
    for (db.prj_order_links.keys()) |link| {
        if (link.prj == idx) {
            try links.append(link);
        }
    }
    std.sort.block(Order.Project_Link, links.items, {}, Order.Project_Link.prj_less_than);
    return links;
}

const log = std.log.scoped(.@"http.prj");

const Transaction = @import("prj/Transaction.zig");
const Project = DB.Project;
const Order = DB.Order;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const slimselect = @import("slimselect.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
