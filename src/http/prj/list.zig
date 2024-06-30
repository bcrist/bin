 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_prj = try req.get_path_param("prj");

    if (missing_prj) |name| if (name.len == 0) {
        try req.redirect("/prj", .moved_permanently);
        return;
    };

    var active_list = std.ArrayList([]const u8).init(http.temp());
    var on_hold_list = std.ArrayList([]const u8).init(http.temp());
    var abandoned_list = std.ArrayList([]const u8).init(http.temp());
    var completed_list = std.ArrayList([]const u8).init(http.temp());

    for (db.prjs.items(.id), db.prjs.items(.parent), db.prjs.items(.status)) |id, parent, status| {
        if (parent == null and id.len > 0) {
            switch (status) {
                .active => try active_list.append(id),
                .on_hold => try on_hold_list.append(id),
                .abandoned => try abandoned_list.append(id),
                .completed => try completed_list.append(id),
            }
        }
    }

    sort.natural(active_list.items);
    sort.natural(on_hold_list.items);
    sort.natural(abandoned_list.items);
    sort.natural(completed_list.items);

    try req.render("prj/list.zk", .{
        .active_list = active_list.items,
        .on_hold_list = on_hold_list.items,
        .abandoned_list = abandoned_list.items,
        .completed_list = completed_list.items,
        .session = session,
        .missing_prj = missing_prj,
    }, .{});
}

pub fn post(req: *http.Request, db: *const DB) !void {
    var q: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        q = try http.temp().dupe(u8, param.value orelse "");
    }

    const results = try search.query(db, http.temp(), q, .{
        .enable_by_kind = .{ .prjs = true },
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

const log = std.log.scoped(.@"http.prj");

const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const search = @import("../../search.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
