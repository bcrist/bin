 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_part = try req.get_path_param("p");
    const missing_part_mfr = try req.get_path_param("mfr");

    if (missing_part) |name| if (name.len == 0) {
        try req.redirect("/p", .moved_permanently);
        return;
    };

    const Part_Info = struct {
        mfr: ?[]const u8,
        id: []const u8,

        pub fn less_than(_: void, a: @This(), b: @This()) bool {
            return sort.natural_less_than({}, a.id, b.id);
        }
    };

    var list = try std.ArrayList(Part_Info).initCapacity(http.temp(), db.parts.len);
    for (db.parts.items(.id), db.parts.items(.mfr), db.parts.items(.parent)) |id, mfr, parent| {
        if (parent == null) {
            list.appendAssumeCapacity(.{
                .mfr = if (mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null,
                .id = id,
            });
        }
    }
    std.sort.block(Part_Info, list.items, {}, Part_Info.less_than);

    try req.render("part/list.zk", .{
        .part_list = list.items,
        .session = session,
        .missing_part = missing_part,
        .missing_part_mfr = missing_part_mfr,
    }, .{});
}

pub fn post(req: *http.Request, db: *const DB) !void {
    var q: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        // TODO check for mfr param
        q = try http.temp().dupe(u8, param.value orelse "");
    }

    const results = try search.query(db, http.temp(), q, .{
        .enable_by_kind = .{ .parts = true },
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
                .value = Part.get_id(db, result.item.part),
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
                .value = Part.get_id(db, result.item.part),
                .text = try result.item.name(db, http.temp()),
            });
        }

        try slimselect.respond_with_options(req, options.items);
    }
}

const log = std.log.scoped(.@"http.part");

const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const search = @import("../../search.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
