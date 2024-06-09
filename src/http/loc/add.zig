pub const validate = @import("add/validate.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const id = (try req.get_path_param("loc")) orelse "";
    const now = std.time.milliTimestamp();
    const loc = Location.init_empty(id, now);

    var parent_id: ?[]const u8 = null;

    var iter = req.query_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "parent")) {
            if (Location.maybe_lookup(db, param.value)) |parent_idx| {
                parent_id = Location.get_id(db, parent_idx);
            }
        } else {
            log.debug("Unrecognized parameter for /loc/add: {s}={s}", .{ param.name, param.value orelse "" });
        }
    }

    try render(loc, .{
        .session = session,
        .req = req,
        .tz = tz,
        .parent_id = parent_id,
        .children = &.{},
        .mode = .add,
    });
}

pub fn post(req: *http.Request, db: *DB) !void {
    var another = false;
    var txn: Transaction = .{
        .db = db,
        .idx = null,
    };

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "another")) {
            another = true;
            continue;
        }
        try txn.process_param(param);
    }

    try txn.validate();
    try txn.apply_changes(db);

    if (another) {
        if (req.get_header("hx-current-url")) |param| {
            const url = param.value;
            if (std.mem.indexOfScalar(u8, url, '?')) |query_start| {
                try req.see_other(try http.tprint("/loc/add{s}", .{ url[query_start..] }));
                return;
            }
        }
        try req.see_other("/loc/add");
    } else {
        try req.see_other(try http.tprint("/loc:{}", .{ http.fmtForUrl(txn.id.?) }));
    }
}

const log = std.log.scoped(.@"http.loc");

const render = @import("../loc.zig").render;
const Transaction = @import("Transaction.zig");
const Location = DB.Location;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
