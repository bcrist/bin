pub const list = @import("pkg/list.zig");
pub const add = @import("pkg/add.zig");
pub const edit = @import("pkg/edit.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req, tz, db);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const pkg = Package.get(db, idx);

    if (!std.mem.eql(u8, requested_pkg_name.?, pkg.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try http.tprint("/pkg:{}", .{ http.percent_encoding.fmtEncoded(pkg.id) }));
        try req.respond("");
        return;
    }

    const parent_id = if (pkg.parent) |parent_idx| Package.get_id(db, parent_idx) else null;
    const mfr_id = if (pkg.manufacturer) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null;

    var children = std.ArrayList([]const u8).init(http.temp());
    for (db.pkgs.items(.parent), db.pkgs.items(.id)) |parent_idx, id| {
        if (parent_idx == idx) {
            try children.append(id);
        }
    }
    sort.natural(children.items);

    try render(pkg, .{
        .session = session,
        .req = req,
        .tz = tz,
        .parent_id = parent_id,
        .children = children.items,
        .mfr_id = mfr_id,
        .mode = if (try req.has_query_param("edit")) .edit else .info,
    });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse return;

    // TODO if there are any parts/etc referencing this pkg, redirect to /pkg:*?error#parts

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

pub const Field = enum {
    id,
    full_name,
    parent,
    mfr,
    notes,
};

const Name_Field = enum {
    id,
    full_name,
};
pub fn validate_name(name: []const u8, db: *const DB, for_pkg: ?Package.Index, for_field: Name_Field, valid: *bool, message: *[]const u8) !?[]const u8 {
    const trimmed = std.mem.trim(u8, name, &std.ascii.whitespace);
    if (for_field == .id and !DB.is_valid_id(trimmed)) {
        log.debug("Invalid ID: {s}", .{ name });
        valid.* = false;
        message.* = "ID may not be empty or '_', or contain '/'";
        return trimmed;
    }

    if (trimmed.len == 0) {
        return null;
    }

    if (Package.maybe_lookup(db, trimmed)) |idx| {

        if (for_pkg) |for_pkg_idx| {
            if (idx == for_pkg_idx) {
                const maybe_current_name: ?[]const u8 = switch (for_field) {
                    .id => Package.get_id(db, idx),
                    .full_name => Package.get_full_name(db, idx),
                };
                if (maybe_current_name) |current_name| {
                    if (std.mem.eql(u8, trimmed, current_name)) {
                        return trimmed;
                    }
                }
            }
        }

        log.debug("Invalid name (in use): {s}", .{ name });
        valid.* = false;
        const id = Package.get_id(db, idx);
        message.* = try http.tprint("In use by <a href=\"/pkg:{}\" target=\"_blank\">{s}</a>", .{ http.percent_encoding.fmtEncoded(id), id });
    }

    return trimmed;
}

const Render_Info = struct {
    session: ?Session,
    req: *http.Request,
    tz: ?*const tempora.Timezone,
    parent_id: ?[]const u8,
    children: []const []const u8,
    mfr_id: ?[]const u8,
    mode: enum {
        info,
        add,
        edit,
    },
};

pub fn render(pkg: Package, info: Render_Info) !void {
    if (info.mode != .info) try Session.redirect_if_missing(info.req, info.session);

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(pkg.created_timestamp_ms, info.tz);
    const modified_dto = DTO.from_timestamp_ms(pkg.modified_timestamp_ms, info.tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    const post_prefix = switch (info.mode) {
        .info => "",
        .edit => try http.tprint("/pkg:{}", .{ http.percent_encoding.fmtEncoded(pkg.id) }),
        .add => "/pkg",
    };

    const data = .{
        .session = info.session,
        .mode = info.mode,
        .post_prefix = post_prefix,
        .title = pkg.full_name orelse pkg.id,
        .obj = pkg,
        .full_name = pkg.full_name orelse pkg.id,
        .parent_id = info.parent_id,
        .mfr_id = info.mfr_id,
        .parent_search_url = "/pkg",
        .cancel_url = "/pkg",
        .children = info.children,
        .created = created_dto,
        .modified = modified_dto,
    };

    switch (info.mode) {
        .info => try info.req.render("pkg/info.zk", data, .{ .Context = Context }),
        .edit => try info.req.render("pkg/edit.zk", data, .{ .Context = Context }),
        .add => try info.req.render("pkg/add.zk", data, .{ .Context = Context }),
    }
}

const log = std.log.scoped(.@"http.pkg");

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const slimselect = @import("slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
