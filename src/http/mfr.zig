pub const list = @import("mfr/list.zig");
pub const add = @import("mfr/add.zig");
pub const edit = @import("mfr/edit.zig");
pub const reorder_additional_names = @import("mfr/reorder_additional_names.zig");
pub const reorder_relations = @import("mfr/reorder_relations.zig");
pub const countries = @import("mfr/countries.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req, db);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const mfr = Manufacturer.get(db, idx);

    if (!std.mem.eql(u8, requested_mfr_name.?, mfr.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try http.tprint("/mfr:{}", .{ http.fmtForUrl(mfr.id) }));
        try req.respond("");
        return;
    }

    if (try req.has_query_param("edit")) {
        try Session.redirect_if_missing(req, session);
        var txn = try Transaction.init_idx(db, idx);
        try txn.render_results(session, req, .{
            .target = .edit,
            .post_prefix = try http.tprint("/mfr:{}", .{ http.fmtForUrl(mfr.id) }),
            .rnd = null,
        });
        return;
    }

    const relations = try get_sorted_relations(db, idx);

    var packages = std.ArrayList([]const u8).init(http.temp());
    for (db.pkgs.items(.id), db.pkgs.items(.manufacturer)) |id, mfr_idx| {
        if (mfr_idx == idx) {
            try packages.append(id);
        }
    }
    sort.natural(packages.items);

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(mfr.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(mfr.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    try req.render("mfr/info.zk", .{
        .session = session,
        .title = mfr.full_name orelse mfr.id,
        .obj = mfr,
        .show_years = mfr.founded_year != null or mfr.suspended_year != null,
        .created = created_dto,
        .modified = modified_dto,
        .relations = relations.items,
        .packages = packages.items,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;

    try Manufacturer.delete(db, idx);

    if (req.get_header("HX-Request")) |_| {
        req.response_status = .no_content;
        try req.add_response_header("HX-Location", "/mfr");
    } else {
        req.response_status = .see_other;
        try req.add_response_header("Location", "/mfr");
    }
    try req.respond("");
}

pub fn get_sorted_relations(db: *const DB, idx: Manufacturer.Index) !std.ArrayList(Relation) {
    var relations = std.ArrayList(Relation).init(http.temp());

    for (0.., db.mfr_relations.items(.source), db.mfr_relations.items(.target)) |i, src, target| {
        if (src == idx) {
            const rel = db.mfr_relations.get(i);
            try relations.append(.{
                .db_index = @enumFromInt(i),
                .is_inverted = false,
                .kind = rel.kind,
                .kind_str = rel.kind.display(),
                .other = Manufacturer.get_id(db, rel.target),
                .year = rel.year,
                .order_index = rel.source_order_index,
            });
        } else if (target == idx) {
            const rel = db.mfr_relations.get(i);
            try relations.append(.{
                .db_index = @enumFromInt(i),
                .is_inverted = true,
                .kind = rel.kind.inverse(),
                .kind_str = rel.kind.inverse().display(),
                .other = Manufacturer.get_id(db, rel.source),
                .year = rel.year,
                .order_index = rel.target_order_index,
            });
        }
    }

    std.sort.block(Relation, relations.items, {}, Relation.less_than);
    return relations;
}

pub const relation_kinds = struct {
    pub fn get(req: *http.Request) !void {
        const Kind = Manufacturer.Relation.Kind;
        try slimselect.respond_with_enum_options(req, Kind, .{
            .placeholder = "Select...",
            .display_fn = Kind.display,
        });
    }
};

pub const Relation = struct {
    db_index: ?Manufacturer.Relation.Index,
    is_inverted: bool,
    kind: Manufacturer.Relation.Kind,
    kind_str: []const u8,
    other: []const u8,
    year: ?u16,
    order_index: u16,

    pub fn less_than(_: void, a: @This(), b: @This()) bool {
        return a.order_index < b.order_index;
    }
};

const log = std.log.scoped(.@"http.mfr");

const Transaction = @import("mfr/Transaction.zig");
const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const slimselect = @import("slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
