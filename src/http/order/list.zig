 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_order = try req.get_path_param("o");

    if (missing_order) |name| if (name.len == 0) {
        try req.redirect("/o", .moved_permanently);
        return;
    };

    var bom_list = std.ArrayList([]const u8).init(http.temp());
    var preparing_list = std.ArrayList([]const u8).init(http.temp());
    var waiting_list = std.ArrayList([]const u8).init(http.temp());
    var arrived_list = std.ArrayList([]const u8).init(http.temp());
    var completed_list = std.ArrayList([]const u8).init(http.temp());
    var cancelled_list = std.ArrayList([]const u8).init(http.temp());

    const s = db.orders.slice();
    const preparing_times = s.items(.preparing_timestamp_ms);
    const waiting_times = s.items(.waiting_timestamp_ms);
    const arrived_times = s.items(.arrived_timestamp_ms);
    const completed_times = s.items(.completed_timestamp_ms);
    const cancelled_times = s.items(.cancelled_timestamp_ms);

    for (0.., s.items(.id)) |i, id| {
        if (id.len > 0) {
            const status: Order.Status = if (cancelled_times[i] != null) .cancelled
                else if (completed_times[i] != null) .completed
                else if (arrived_times[i] != null) .arrived
                else if (waiting_times[i] != null) .waiting
                else if (preparing_times[i] != null) .preparing
                else .none;

            switch (status) {
                .none => try bom_list.append(id),
                .preparing => try preparing_list.append(id),
                .waiting => try waiting_list.append(id),
                .arrived => try arrived_list.append(id),
                .completed => try completed_list.append(id),
                .cancelled => try cancelled_list.append(id),
            }
        }
    }

    sort.natural(bom_list.items);
    sort.natural(preparing_list.items);
    sort.natural(waiting_list.items);
    sort.natural(arrived_list.items);
    sort.natural(completed_list.items);
    sort.natural(cancelled_list.items);

    try req.render("order/list.zk", .{
        .bom_list = bom_list.items,
        .preparing_list = preparing_list.items,
        .waiting_list = waiting_list.items,
        .arrived_list = arrived_list.items,
        .completed_list = completed_list.items,
        .cancelled_list = cancelled_list.items,
        .session = session,
        .missing_order = missing_order,
    }, .{});
}

pub fn post(req: *http.Request, db: *const DB) !void {
    var q: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        q = try http.temp().dupe(u8, param.value orelse "");
    }

    const results = try search.query(db, http.temp(), q, .{
        .enable_by_kind = .{ .orders = true },
        .max_results = 200,
    });

    if (req.get_header("hx-request") != null) {
        const Option = struct {
            value: []const u8,
            text: []const u8,
        };
        var options = try std.ArrayList(Option).initCapacity(http.temp(), results.len);
        for (results) |result| {
            options.appendAssumeCapacity(.{
                .value = try result.item.name(db, http.temp()),
                .text = try result.item.name(db, http.temp()),
            });
        }

        try req.render("search_options.zk", options.items, .{});
    } else {
        var options = try std.ArrayList(slimselect.Option).initCapacity(http.temp(), results.len + 1);
        try options.append(.{
            .placeholder = true,
            .value = "",
            .text = "Select...",
        });
        for (results) |result| {
            options.appendAssumeCapacity(.{
                .value = try result.item.name(db, http.temp()),
                .text = try result.item.name(db, http.temp()),
            });
        }

        try slimselect.respond_with_options(req, options.items);
    }
}

const log = std.log.scoped(.@"http.order");

const Order = DB.Order;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const search = @import("../../search.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
