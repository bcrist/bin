pub const Option = struct {
    value: []const u8,
    text: []const u8 = "",
    relevance: f64 = 0,
    url: []const u8,

    pub fn order(_: void, a: Option, b: Option) bool {
        return a.relevance > b.relevance;
    }
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

    var options = try std.ArrayList(Option).initCapacity(http.temp(), 100);

    if (std.mem.startsWith(u8, q, "mfr:")) {
        q = q["mfr:".len..];
    }

    if (q.len > 0) {
        var name_iter = db.mfr_lookup.iterator();
        while (name_iter.next()) |entry| {
            const name = entry.key_ptr.*;
            if (std.ascii.indexOfIgnoreCase(name, q)) |start_of_match| {
                const url = try http.tprint("/mfr:{s}", .{ Manufacturer.get_id(db, entry.value_ptr.*) });

                var relevance: f64 = @floatFromInt(q.len);
                relevance /= @floatFromInt(1 + name.len - q.len);
                if (start_of_match == 0) {
                    relevance *= 2;
                }

                try options.append(.{
                    .value = url[1..],
                    .text = name,
                    .relevance = relevance,
                    .url = url,
                });
            }
        }
        std.sort.block(Option, options.items, {}, Option.order);
    }

    if (go and options.items.len > 0) {
        try req.set_response_header("HX-Location", options.items[0].url);
        req.response_status = .no_content;
        try req.respond("");
        return;
    }

    try req.render("search_options.zk", options.items, .{});
}

const log = std.log.scoped(.@"http.search");

const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const http = @import("http");
const std = @import("std");
