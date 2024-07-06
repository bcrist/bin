pub const list = @import("order/list.zig");
pub const add = @import("order/add.zig");
pub const edit = @import("order/edit.zig");

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

const log = std.log.scoped(.@"http.order");

const Transaction = @import("order/Transaction.zig");
const Order = DB.Order;
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const slimselect = @import("slimselect.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
