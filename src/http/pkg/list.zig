 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_pkg = try req.get_path_param("pkg");

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
    var name_filter: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "name")) {
            name_filter = try http.temp().dupe(u8, param.value orelse "");
        } else {
            log.warn("Unrecognized search filter: {s}={s}", .{ param.name, param.value orelse "" });
        }
    }

    var options = try std.ArrayList(slimselect.Option).initCapacity(http.temp(), db.pkg_lookup.size + 1);

    try options.append(.{
        .placeholder = true,
        .value = "",
        .text = "Select...",
    });

    var name_iter = db.pkg_lookup.iterator();
    while (name_iter.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name_filter.len == 0 or std.ascii.indexOfIgnoreCase(name, name_filter) != null) {
            options.appendAssumeCapacity(.{
                .value = Package.get_id(db, entry.value_ptr.*),
                .text = entry.key_ptr.*,
            });
        }
    }

    std.sort.block(slimselect.Option, options.items, {}, slimselect.Option.less_than);
    try slimselect.respond_with_options(req, options.items);
}

const log = std.log.scoped(.@"http.pkg");

const Package = DB.Package;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
