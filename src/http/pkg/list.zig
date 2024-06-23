 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_pkg = try req.get_path_param("pkg");

    if (missing_pkg) |name| if (name.len == 0) {
        try req.redirect("/pkg", .moved_permanently);
        return;
    };

    var list = try std.ArrayList([]const u8).initCapacity(http.temp(), db.pkgs.len);
    for (db.pkgs.items(.id), db.pkgs.items(.parent)) |id, parent| {
        if (parent == null) {
            list.appendAssumeCapacity(id);
        }
    }
    sort.natural(list.items);

    try req.render("pkg/list.zk", .{
        .pkg_list = list.items,
        .session = session,
        .missing_pkg = missing_pkg,
    }, .{});
}

pub fn post(req: *http.Request, db: *const DB) !void {
    var q: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        q = try http.temp().dupe(u8, param.value orelse "");
    }

    const results = try search.query(db, http.temp(), q, .{
        .enable_by_kind = .{ .pkgs = true },
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

const log = std.log.scoped(.@"http.pkg");

const Package = DB.Package;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const search = @import("../../search.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
