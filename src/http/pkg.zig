pub const list = @import("pkg/list.zig");
pub const add = @import("pkg/add.zig");
pub const edit = @import("pkg/edit.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req, db);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const pkg = Package.get(db, idx);

    if (!std.mem.eql(u8, requested_pkg_name.?, pkg.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try http.tprint("/pkg:{}", .{ http.fmtForUrl(pkg.id) }));
        try req.respond("");
        return;
    }

    if (try req.has_query_param("edit")) {
        try Session.redirect_if_missing(req, session);
        var txn = try Transaction.init_idx(db, idx);
        try txn.render_results(session, req, .{
            .target = .edit,
            .post_prefix = try http.tprint("/pkg:{}", .{ http.fmtForUrl(pkg.id) }),
            .rnd = null,
        });
        return;
    }

    const parent_id = if (pkg.parent) |parent_idx| Package.get_id(db, parent_idx) else null;
    const mfr_id = if (pkg.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null;

    var children = std.ArrayList([]const u8).init(http.temp());
    for (db.pkgs.items(.parent), db.pkgs.items(.id)) |parent_idx, id| {
        if (parent_idx == idx) {
            try children.append(id);
        }
    }
    sort.natural(children.items);

     const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(pkg.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(pkg.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    try req.render("pkg/info.zk", .{
        .session = session,
        .title = pkg.full_name orelse pkg.id,
        .obj = pkg,
        .parent_id = parent_id,
        .mfr_id = mfr_id,
        .children = children.items,
        .created = created_dto,
        .modified = modified_dto,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse return;

    try Package.delete(db, idx, true);

    if (req.get_header("HX-Request")) |_| {
        req.response_status = .no_content;
        try req.add_response_header("HX-Location", "/pkg");
    } else {
        req.response_status = .see_other;
        try req.add_response_header("Location", "/pkg");
    }
    try req.respond("");
}

const log = std.log.scoped(.@"http.pkg");

const Transaction = @import("pkg/Transaction.zig");
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
