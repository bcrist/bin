pub fn post(req: *http.Request, db: *DB) !void {
    const requested_order_name = try req.get_path_param("o");
    const idx = Order.maybe_lookup(db, requested_order_name) orelse return;

    var list = try order.get_sorted_project_links(db, idx);
    var apply_changes = true;

    var ordering: u16 = 0;
    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const expected_prefix = "prj_ordering";
        if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
        const index_str = param.name[expected_prefix.len..];
        if (index_str.len == 0) continue;
        const index = std.fmt.parseUnsigned(usize, index_str, 10) catch {
            apply_changes = false;
            break;
        };
        if (index >= list.items.len) {
            apply_changes = false;
        }

        list.items[index].order_ordering = ordering;
        ordering += 1;
    }

    if (apply_changes) {
        for (list.items) |link| {
            const link_idx = try Order.Project_Link.lookup_or_create(db, .{
                .order = link.order,
                .prj = link.prj,
            });
            try Order.Project_Link.set_order_ordering(db, link_idx, link.order_ordering);
        }
        std.sort.block(Order.Project_Link, list.items, {}, Order.Project_Link.order_less_than);
    }

    const project_ids = db.prjs.items(.id);
    const post_prefix = try Transaction.get_post_prefix(db, idx);
    for (0.., list.items) |i, link| {
        try req.render("order/post_project.zk", .{
            .valid = true,
            .post_prefix = post_prefix,
            .index = i,
            .prj_id = project_ids[link.prj.raw()],
        }, .{});
    }
    try req.render("order/post_project_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
}

const Transaction = @import("Transaction.zig");
const Project = DB.Project;
const Order = DB.Order;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const order = @import("../order.zig");
const http = @import("http");
const std = @import("std");
