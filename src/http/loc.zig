pub const list = @import("loc/list.zig");
pub const add = @import("loc/add.zig");
pub const edit = @import("loc/edit.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_loc_name = try req.get_path_param("loc");
    const idx = Location.maybe_lookup(db, requested_loc_name) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req, tz, db);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const loc = Location.get(db, idx);

    if (!std.mem.eql(u8, requested_loc_name.?, loc.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try http.tprint("/loc:{}", .{ http.fmtForUrl(loc.id) }));
        try req.respond("");
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

    try render(loc, .{
        .session = session,
        .req = req,
        .tz = tz,
        .parent_id = parent_id,
        .children = children.items,
        .mode = if (try req.has_query_param("edit")) .edit else .info,
    });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_loc_name = try req.get_path_param("loc");
    const idx = Location.maybe_lookup(db, requested_loc_name) orelse return;

    // TODO if there are any parts/etc referencing this loc, redirect to /loc:*?error#parts

    try Location.delete(db, idx, true);

    if (req.get_header("HX-Request")) |_| {
        req.response_status = .no_content;
        try req.add_response_header("HX-Location", "/loc");
    } else {
        req.response_status = .see_other;
        try req.add_response_header("Location", "/loc");
    }
    try req.respond("");
}

const Render_Info = struct {
    session: ?Session,
    req: *http.Request,
    tz: ?*const tempora.Timezone,
    parent_id: ?[]const u8,
    children: []const []const u8,
    mode: enum {
        info,
        add,
        edit,
    },
};

pub fn render(loc: Location, info: Render_Info) !void {
    if (info.mode != .info) try Session.redirect_if_missing(info.req, info.session);

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(loc.created_timestamp_ms, info.tz);
    const modified_dto = DTO.from_timestamp_ms(loc.modified_timestamp_ms, info.tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    const post_prefix = switch (info.mode) {
        .info => "",
        .edit => try http.tprint("/loc:{}", .{ http.fmtForUrl(loc.id) }),
        .add => "/loc",
    };

    const data = .{
        .session = info.session,
        .mode = info.mode,
        .post_prefix = post_prefix,
        .title = loc.full_name orelse loc.id,
        .obj = loc,
        .parent_id = info.parent_id,
        .parent_search_url = "/loc",
        .cancel_url = "/loc",
        .children = info.children,
        .created = created_dto,
        .modified = modified_dto,
    };

    switch (info.mode) {
        .info => try info.req.render("loc/info.zk", data, .{ .Context = Context }),
        .edit => try info.req.render("loc/edit.zk", data, .{ .Context = Context }),
        .add => try info.req.render("loc/add.zk", data, .{ .Context = Context }),
    }
}

const log = std.log.scoped(.@"http.loc");

const Location = DB.Location;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const slimselect = @import("slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
