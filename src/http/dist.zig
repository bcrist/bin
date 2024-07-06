pub const list = @import("dist/list.zig");
pub const add = @import("dist/add.zig");
pub const edit = @import("dist/edit.zig");
pub const reorder_additional_names = @import("dist/reorder_additional_names.zig");
pub const reorder_relations = @import("dist/reorder_relations.zig");
pub const countries = @import("dist/countries.zig");

pub const relation_kinds = struct {
    pub fn get(req: *http.Request) !void {
        const Kind = Distributor.Relation.Kind;
        try slimselect.respond_with_enum_options(req, Kind, .{
            .placeholder = "Select...",
            .display_fn = Kind.display,
        });
    }
};

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_dist_name = try req.get_path_param("dist");
    const idx = Distributor.maybe_lookup(db, requested_dist_name) orelse {
        try list.get(session, req, db);
        return;
    };
    const dist = Distributor.get(db, idx);

    if (!std.mem.eql(u8, requested_dist_name.?, dist.id)) {
        try req.redirect(try http.tprint("/dist:{}", .{ http.fmtForUrl(dist.id) }), .moved_permanently);
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

    const relations = try get_sorted_relations(db, idx);

    var active_orders = std.ArrayList([]const u8).init(http.temp());
    const order_completed_times = db.orders.items(.completed_timestamp_ms);
    const order_cancelled_times = db.orders.items(.cancelled_timestamp_ms);
    const order_ids = db.orders.items(.id);
    for (0.., db.orders.items(.dist)) |i, dist_idx| {
        if (dist_idx != idx or order_completed_times[i] != null or order_cancelled_times[i] != null) continue;

        const order = db.orders.get(i);
        if (order.get_status() == .none) continue;
        
        try active_orders.append(order_ids[i]);
    }
    sort.natural(active_orders.items);

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(dist.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(dist.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    try req.render("dist/info.zk", .{
        .session = session,
        .title = dist.full_name orelse dist.id,
        .obj = dist,
        .show_years = dist.founded_year != null or dist.suspended_year != null,
        .active_orders = active_orders.items,
        .created = created_dto,
        .modified = modified_dto,
        .relations = relations.items,
    }, .{ .Context = Context });
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_dist_name = try req.get_path_param("dist");
    const idx = Distributor.maybe_lookup(db, requested_dist_name) orelse return;

    try Distributor.delete(db, idx);

    try req.redirect("/dist", .see_other);
}

pub fn get_sorted_relations(db: *const DB, idx: Distributor.Index) !std.ArrayList(Relation) {
    var relations = std.ArrayList(Relation).init(http.temp());

    for (0.., db.dist_relations.items(.source), db.dist_relations.items(.target)) |i, src, target| {
        if (src == idx) {
            const rel = db.dist_relations.get(i);
            try relations.append(.{
                .db_index = Distributor.Relation.Index.init(i),
                .is_inverted = false,
                .kind = rel.kind,
                .kind_str = rel.kind.display(),
                .other = Distributor.get_id(db, rel.target),
                .year = rel.year,
                .order_index = rel.source_order_index,
            });
        } else if (target == idx) {
            const rel = db.dist_relations.get(i);
            try relations.append(.{
                .db_index = Distributor.Relation.Index.init(i),
                .is_inverted = true,
                .kind = rel.kind.inverse(),
                .kind_str = rel.kind.inverse().display(),
                .other = Distributor.get_id(db, rel.source),
                .year = rel.year,
                .order_index = rel.target_order_index,
            });
        }
    }

    std.sort.block(Relation, relations.items, {}, Relation.less_than);
    return relations;
}

pub const Relation = struct {
    db_index: ?Distributor.Relation.Index,
    is_inverted: bool,
    kind: Distributor.Relation.Kind,
    kind_str: []const u8,
    other: []const u8,
    year: ?u16,
    order_index: u16,

    pub fn less_than(_: void, a: @This(), b: @This()) bool {
        return a.order_index < b.order_index;
    }
};

const log = std.log.scoped(.@"http.dist");

const Transaction = @import("dist/Transaction.zig");
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const slimselect = @import("slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
