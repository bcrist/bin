pub const Option = struct {
    value: []const u8,
    text: []const u8,
};

pub fn post(req: *http.Request, db: *const DB) !void {
    var q: []const u8 = "";
    var go = false;

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "q")) {
            q = try http.temp().dupe(u8, param.value orelse "");
        } else if (std.mem.eql(u8, param.name, "go")) {
            if (std.mem.eql(u8, param.value orelse "true", "true")) {
                go = true;
            } else return error.BadRequest;
        } else {
            log.warn("Unrecognized search filter: {s}={s}", .{ param.name, param.value orelse "" });
            return error.BadRequest;
        }
    }

    if (go) {
        if (std.mem.startsWith(u8, q, "/")) {
            try req.redirect(q, .see_other);
            return;
        } else {
            const results = try search.query(db, http.temp(), q, .{ .max_results = 1 });
            if (results.len > 0) {
                try req.redirect(try results[0].url(db, http.temp()), .see_other);
                return;
            }
        }
    }

    const results = try search.query(db, http.temp(), q, .{ .max_results = 200 });

    if (req.get_header("hx-request") != null) {
        var options = try std.ArrayList(Option).initCapacity(http.temp(), results.len);
        for (results) |result| {
            options.appendAssumeCapacity(.{
                .value = try result.url(db, http.temp()),
                .text = try result.item.name(db, http.temp()),
            });
        }

        try req.render("search_options.zk", options.items, .{});
    } else {
        var options = try std.ArrayList(slimselect.Option).initCapacity(http.temp(), results.len);
        for (results) |result| {
            options.appendAssumeCapacity(.{
                .value = try result.url(db, http.temp()),
                .text = try result.item.name(db, http.temp()),
            });
        }

        try slimselect.respond_with_options(req, options.items);
    }
}

const log = std.log.scoped(.@"http.search");

const slimselect = @import("slimselect.zig");
const search = @import("../search.zig");
const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const http = @import("http");
const std = @import("std");
