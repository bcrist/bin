 pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const missing_mfr = try req.get_path_param("mfr");

    const mfr_list = try http.temp().dupe([]const u8, db.mfrs.items(.id));
    sort.natural(mfr_list);

    try req.render("mfr/list.zk", .{
        .mfr_list = mfr_list,
        .session = session,
        .missing_mfr = missing_mfr,
    }, .{});
}

pub fn post(req: *http.Request, db: *const DB) !void {
    var name_filter: []const u8 = "";

    var param_iter = try req.form_iterator();
    while (try param_iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "name")) {
            name_filter = param.value orelse "";
        } else {
            log.warn("Unrecognized search filter: {s}={s}", .{ param.name, param.value orelse "" });
        }
    }

    const ids = db.mfrs.items(.id);
    var options = try std.ArrayList(slimselect.Option).initCapacity(http.temp(), db.mfr_lookup.size + 1);

    try options.append(.{
        .placeholder = true,
        .value = "",
        .text = "Select...",
    });

    var name_iter = db.mfr_lookup.iterator();
    while (name_iter.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name_filter.len == 0 or std.ascii.indexOfIgnoreCase(name, name_filter) != null) {
            options.appendAssumeCapacity(.{
                .value = ids[@intFromEnum(entry.value_ptr.*)],
                .text = entry.key_ptr.*,
            });
        }
    }

    std.sort.block(slimselect.Option, options.items, {}, slimselect.Option.less_than);
    try slimselect.respond_with_options(req, options.items);
}

const log = std.log.scoped(.@"http.mfr");

const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
