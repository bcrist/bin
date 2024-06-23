pub const list = @import("loc/list.zig");
pub const add = @import("loc/add.zig");
pub const edit = @import("loc/edit.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_loc_name = try req.get_path_param("loc");
    const idx = Location.maybe_lookup(db, requested_loc_name) orelse {
        try list.get(session, req, db);
        return;
    };
    const loc = Location.get(db, idx);

    if (!std.mem.eql(u8, requested_loc_name.?, loc.id)) {
        try req.redirect(try http.tprint("/loc:{}", .{ http.fmtForUrl(loc.id) }), .moved_permanently);
        return;
    }

    if (try req.has_query_param("edit")) {
        try Session.redirect_if_missing(req, session);
        var txn = try Transaction.init_idx(db, idx);
        try txn.render_results(session, req, .{
            .target = .edit,
            .rnd = null,
        });
        return;
    }

    const parent_id = if (loc.parent) |parent_idx| Location.get_id(db, parent_idx) else null;

    var children = std.ArrayList([]const u8).init(http.temp());
    for (db.locs.items(.parent), db.locs.items(.id)) |parent_idx, id| {
        if (parent_idx == idx) {
            try children.append(id);
        }
    }
    sort.natural(children.items);

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(loc.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(loc.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    try req.render("loc/info.zk", .{
        .session = session,
        .title = loc.full_name orelse loc.id,
        .obj = loc,
        .parent_id = parent_id,
        .children = children.items,
        .created = created_dto,
        .modified = modified_dto,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_loc_name = try req.get_path_param("loc");
    const idx = Location.maybe_lookup(db, requested_loc_name) orelse return;

    try Location.delete(db, idx, true);

    try req.redirect("/loc", .see_other);
}

const log = std.log.scoped(.@"http.loc");

const Transaction = @import("loc/Transaction.zig");
const Location = DB.Location;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
