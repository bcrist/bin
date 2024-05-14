

pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const requested = try req.get_path_param("mfr");
    const idx = db.mfr_lookup.get(requested.?) orelse {
        try list.get(session, req, db);
        return;
    };
    const mfr = db.mfrs.get(@intFromEnum(idx));

    if (!std.mem.eql(u8, requested.?, mfr.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try std.fmt.allocPrint(http.temp(), "/mfr:{s}", .{ mfr.id }));
        try req.respond("");
        return;
    }

    const Relation = struct {
        kind: []const u8,
        other: []const u8,
        year: ?u16,
        order_index: u16,

        pub fn less_than(_: void, a: @This(), b: @This()) bool {
            return a.order_index < b.order_index;
        }
    };

    var relations = std.ArrayList(Relation).init(http.temp());

    for (0.., db.mfr_relations.items(.source), db.mfr_relations.items(.target)) |i, src, target| {
        if (src == idx) {
            const rel = db.mfr_relations.get(i);
            try relations.append(.{
                .kind = rel.kind.display(),
                .other = db.mfrs.items(.id)[@intFromEnum(rel.target)],
                .year = rel.year,
                .order_index = rel.source_order_index,
            });
        } else if (target == idx) {
            const rel = db.mfr_relations.get(i);
            try relations.append(.{
                .kind = rel.kind.inverse().display(),
                .other = db.mfrs.items(.id)[@intFromEnum(rel.source)],
                .year = rel.year,
                .order_index = rel.target_order_index,
            });
        }
    }

    std.sort.block(Relation, relations.items, {}, Relation.less_than);

    const tz = try tempora.tzdb.timezone(if (session) |s| s.timezone else "GMT");

    const created_dto = tempora.Date_Time.With_Offset.from_timestamp_ms(mfr.created_timestamp_ms, tz);
    const modified_dto = tempora.Date_Time.With_Offset.from_timestamp_ms(mfr.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = tempora.Date_Time.With_Offset.fmt_sql;
        pub const modified = tempora.Date_Time.With_Offset.fmt_sql;
    };

    if (try req.has_query_param("edit")) {
        try Session.redirect_if_missing(req, session);

        try req.render("mfr/edit.zk", .{
            .mfr = mfr,
            .session = session,
            .full_name = mfr.full_name orelse mfr.id,
            .created = created_dto,
            .modified = modified_dto,
            .relations = relations.items,
        }, .{ .Context = Context });
    } else {
        try req.render("mfr/info.zk", .{
            .mfr = mfr,
            .session = session,
            .full_name = mfr.full_name orelse mfr.id,
            .created = created_dto,
            .modified = modified_dto,
            .relations = relations.items,
        }, .{ .Context = Context });
    }
}

pub const list = struct {
    pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
        const missing_mfr = try req.get_path_param("mfr");

        const mfr_list = try http.temp().dupe([]const u8, db.mfrs.items(.id));
        sort.lexicographic(mfr_list);

        try req.render("mfr/list.zk", .{
            .mfr_list = mfr_list,
            .session = session,
            .missing_mfr = missing_mfr,
        }, .{});
    }
};

pub const add = struct {
    pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
        _ = db;
        try Session.redirect_if_missing(req, session);

        try req.render("mfr/edit.zk", .{
            .session = session,
        }, .{});
    }
};

const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
