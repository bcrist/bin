pub const list = @import("pkg/list.zig");
pub const add = @import("pkg/add.zig");
pub const edit = @import("pkg/edit.zig");
pub const reorder_additional_names = @import("pkg/reorder_additional_names.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const requested_pkg_name = try req.get_path_param("pkg");
    const maybe_mfr_idx = Manufacturer.maybe_lookup(db, requested_mfr_name);
    const idx = Package.maybe_lookup(db, maybe_mfr_idx, requested_pkg_name) orelse {
        try list.get(session, req, db);
        return;
    };

    const expected_url = try Transaction.get_post_prefix(db, idx);
    if (!std.mem.eql(u8, req.full_path, expected_url)) {
        try req.redirect(expected_url, .moved_permanently);
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

    const pkg = Package.get(db, idx);
    const mfr_id = if (pkg.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null;
    var parent_id: ?[]const u8 = null;
    var parent_mfr_id: ?[]const u8 = null;

    if (pkg.parent) |parent_idx| {
        const parent_mfr = Package.get_mfr(db, parent_idx);
        if (parent_mfr) |mfr_idx| {
            parent_mfr_id = Manufacturer.get_id(db, mfr_idx);
        }
        parent_id = Package.get_id(db, parent_idx);
    }

    var children = std.ArrayList(Package_Info).init(http.temp());
    for (db.pkgs.items(.parent), db.pkgs.items(.id), db.pkgs.items(.mfr)) |parent_idx, id, maybe_child_mfr_idx| {
        if (parent_idx == idx) {
            try children.append(.{
                .mfr_id = if (maybe_child_mfr_idx) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null,
                .id = id,
            });
        }
    }
    std.sort.block(Package_Info, children.items, {}, Package_Info.less_than);

    var parts = std.ArrayList(part.Part_Info).init(http.temp());
    for (db.parts.items(.pkg), db.parts.items(.id), db.parts.items(.mfr)) |pkg_idx, id, maybe_part_mfr_idx| {
        if (pkg_idx == idx) {
            try parts.append(.{
                .mfr_id = if (maybe_part_mfr_idx) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null,
                .id = id,
            });
        }
    }
    std.sort.block(part.Part_Info, parts.items, {}, part.Part_Info.less_than);

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
        .parent_mfr = parent_mfr_id,
        .mfr_id = mfr_id,
        .children = children.items,
        .parts = parts.items,
        .created = created_dto,
        .modified = modified_dto,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const requested_pkg_name = try req.get_path_param("pkg");
    const maybe_mfr_idx = Manufacturer.maybe_lookup(db, requested_mfr_name);
    const idx = Package.maybe_lookup(db, maybe_mfr_idx, requested_pkg_name) orelse return;

    try Package.delete(db, idx, true);

    try req.redirect("/pkg", .see_other);
}

pub const Package_Info = struct {
    mfr_id: ?[]const u8,
    id: []const u8,

    pub fn less_than(_: void, a: @This(), b: @This()) bool {
        return sort.natural_less_than({}, a.id, b.id);
    }
};

const log = std.log.scoped(.@"http.pkg");

const Transaction = @import("pkg/Transaction.zig");
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const part = @import("part.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
