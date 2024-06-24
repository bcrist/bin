pub const list = @import("part/list.zig");
pub const add = @import("part/add.zig");
pub const edit = @import("part/edit.zig");
pub const reorder_dist_pns = @import("part/reorder_dist_pns.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const requested_part_name = try req.get_path_param("p");
    const maybe_mfr_idx = Manufacturer.maybe_lookup(db, requested_mfr_name);
    const idx = Part.maybe_lookup(db, maybe_mfr_idx, requested_part_name) orelse {
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

    const part = Part.get(db, idx);
    const mfr_id = if (part.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null;
    const pkg_id = if (part.pkg) |pkg_idx| Package.get_id(db, pkg_idx) else null;
    var parent_id: ?[]const u8 = null;
    var parent_mfr_id: ?[]const u8 = null;

    if (part.parent) |parent_idx| {
        const parent_mfr = Part.get_mfr(db, parent_idx);
        if (parent_mfr) |mfr_idx| {
            parent_mfr_id = Manufacturer.get_id(db, mfr_idx);
        }
        parent_id = Part.get_id(db, parent_idx);
    }

    var children = std.ArrayList(Part_Info).init(http.temp());
    for (db.parts.items(.parent), db.parts.items(.id), db.parts.items(.mfr)) |parent_idx, id, maybe_child_mfr_idx| {
        if (parent_idx == idx) {
            try children.append(.{
                .mfr_id = if (maybe_child_mfr_idx) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null,
                .id = id,
            });
        }
    }
    std.sort.block(Part_Info, children.items, {}, Part_Info.less_than);

    var dist_pns = try std.ArrayList(Distributor_Part_Number).initCapacity(http.temp(), part.dist_pns.items.len);
    for (part.dist_pns.items) |pn| {
        dist_pns.appendAssumeCapacity(.{
            .dist = Distributor.get_id(db, pn.dist),
            .pn = pn.pn,
        });
    }

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(part.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(part.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    try req.render("part/info.zk", .{
        .session = session,
        .title = part.id,
        .obj = part,
        .parent_id = parent_id,
        .parent_mfr = parent_mfr_id,
        .mfr_id = mfr_id,
        .pkg_id = pkg_id,
        .dist_pns = dist_pns.items,
        .children = children.items,
        .created = created_dto,
        .modified = modified_dto,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const requested_part_name = try req.get_path_param("p");
    const maybe_mfr_idx = Manufacturer.maybe_lookup(db, requested_mfr_name);
    const idx = Part.maybe_lookup(db, maybe_mfr_idx, requested_part_name) orelse return;

    try Part.delete(db, idx, true);

    try req.redirect("/p", .see_other);
}

pub const Part_Info = struct {
    mfr_id: ?[]const u8,
    id: []const u8,

    pub fn less_than(_: void, a: @This(), b: @This()) bool {
        return sort.natural_less_than({}, a.id, b.id);
    }
};

pub const Distributor_Part_Number = struct {
    dist: []const u8,
    pn: []const u8,
};

const log = std.log.scoped(.@"http.part");

const Transaction = @import("part/Transaction.zig");
const Part = DB.Part;
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
