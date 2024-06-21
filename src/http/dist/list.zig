 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_dist = try req.get_path_param("dist");

    if (missing_dist) |name| if (name.len == 0) {
        try req.redirect("/dist", .moved_permanently);
        return;
    };

    const dist_list = try http.temp().dupe([]const u8, db.dists.items(.id));
    sort.natural(dist_list);

    try req.render("dist/list.zk", .{
        .dist_list = dist_list,
        .session = session,
        .missing_dist = missing_dist,
    }, .{});
}

pub fn post(req: *http.Request, db: *const DB) !void {
    var name_filter: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "name")) {
            name_filter = try http.temp().dupe(u8, param.value orelse "");
        } else {
            log.warn("Unrecognized search filter: {s}={s}", .{ param.name, param.value orelse "" });
        }
    }

    var options = try std.ArrayList(slimselect.Option).initCapacity(http.temp(), db.dist_lookup.size + 1);

    try options.append(.{
        .placeholder = true,
        .value = "",
        .text = "Select...",
    });

    var name_iter = db.dist_lookup.iterator();
    while (name_iter.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name_filter.len == 0 or std.ascii.indexOfIgnoreCase(name, name_filter) != null) {
            options.appendAssumeCapacity(.{
                .value = Distributor.get_id(db, entry.value_ptr.*),
                .text = entry.key_ptr.*,
            });
        }
    }

    std.sort.block(slimselect.Option, options.items, {}, slimselect.Option.less_than);
    try slimselect.respond_with_options(req, options.items);
}

const log = std.log.scoped(.@"http.dist");

const Distributor = DB.Distributor;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
