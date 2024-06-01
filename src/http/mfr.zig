pub const list = @import("mfr/list.zig");
pub const add = @import("mfr/add.zig");
pub const edit = @import("mfr/edit.zig");
pub const countries = @import("mfr/countries.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, db: *const DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req, tz);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const mfr = db.mfrs.get(@intFromEnum(idx));

    if (!std.mem.eql(u8, requested_mfr_name.?, mfr.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try http.tprint("/mfr:{}", .{ http.percent_encoding.fmtEncoded(mfr.id) }));
        try req.respond("");
        return;
    }

    const relations = try get_sorted_relations(db, idx);

    try render(session, req, tz, mfr, relations.items, if (try req.has_query_param("edit")) .edit else .info);
}

pub fn delete(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;

    // TODO if there are any parts/etc referencing this Mfr, redirect to /mfr:*?error#parts

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

pub const Field = enum {
    id,
    full_name,
    country,
    founded_year,
    suspended_year,
    notes,
    website,
    wiki,
};

const Name_Field = union (enum) {
    id,
    full_name,
    additional_name: ?usize,
};
pub fn validate_name(name: []const u8, db: *const DB, for_mfr: ?Manufacturer.Index, for_field: Name_Field, valid: *bool, message: *[]const u8) !?[]const u8 {
    const trimmed = std.mem.trim(u8, name, &std.ascii.whitespace);
    if (for_field == .id and !DB.is_valid_id(trimmed)) {
        log.debug("Invalid ID: {s}", .{ name });
        valid.* = false;
        message.* = "ID may not be empty or '_', or contain '/'";
        return trimmed;
    }

    if (trimmed.len == 0) {
        if (for_field == .additional_name) {
            log.debug("Additional name cannot be empty", .{});
            valid.* = false;
            message.* = "Additional name must be provided";
        }
        return null;
    }

    if (Manufacturer.maybe_lookup(db, trimmed)) |idx| {
        const i = @intFromEnum(idx);
        const id = db.mfrs.items(.id)[i];

        if (for_mfr) |for_mfr_idx| {
            if (idx == for_mfr_idx) {
                const maybe_current_name: ?[]const u8 = switch (for_field) {
                    .id => id,
                    .full_name => db.mfrs.items(.full_name)[i],
                    .additional_name => |maybe_additional_name_index| current: {
                        if (maybe_additional_name_index) |n| {
                            const additional_names = db.mfrs.items(.additional_names)[i].items;
                            if (n < additional_names.len) {
                                break :current additional_names[n];
                            }
                        }
                        break :current null;
                    },
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
        message.* = try http.tprint("In use by <a href=\"/mfr:{}\" target=\"_blank\">{s}</a>", .{ http.percent_encoding.fmtEncoded(id), id });
    }

    return trimmed;
}

pub fn validate_year(str_value: []const u8, valid: *bool, message: *[]const u8) !?u16 {
    const trimmed = std.mem.trim(u8, str_value, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        return null;
    }
    return std.fmt.parseInt(u16, str_value, 10) catch {
        log.debug("Invalid Year: {s}", .{ str_value });
        valid.* = false;
        message.* = try http.tprint("'{s}' is not a valid year!", .{ str_value });
        return null;
    };
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
                .other = db.mfrs.items(.id)[@intFromEnum(rel.target)],
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
                .other = db.mfrs.items(.id)[@intFromEnum(rel.source)],
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

const Render_Mode = enum {
    info,
    add,
    edit,
};

pub fn render(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone, mfr: Manufacturer, relations: []const Relation, mode: Render_Mode) !void {
    if (mode != .info) try Session.redirect_if_missing(req, session);

    const DTO = tempora.Date_Time.With_Offset;

    const created_dto = DTO.from_timestamp_ms(mfr.created_timestamp_ms, tz);
    const modified_dto = DTO.from_timestamp_ms(mfr.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = DTO.fmt_sql;
        pub const modified = DTO.fmt_sql;
    };

    const post_prefix = switch (mode) {
        .info => "",
        .edit => try http.tprint("/mfr:{}", .{ http.percent_encoding.fmtEncoded(mfr.id) }),
        .add => "/mfr",
    };

    const data = .{
        .session = session,
        .mode = mode,
        .post_prefix = post_prefix,
        .title = mfr.full_name orelse mfr.id,
        .mfr = mfr,
        .full_name = mfr.full_name orelse mfr.id,
        .show_years = mfr.founded_year != null or mfr.suspended_year != null,
        .created = created_dto,
        .modified = modified_dto,
        .relations = relations,
    };

    switch (mode) {
        .info => try req.render("mfr/info.zk", data, .{ .Context = Context }),
        .edit => try req.render("mfr/edit.zk", data, .{ .Context = Context }),
        .add => try req.render("mfr/add.zk", data, .{ .Context = Context }),
    }
}

const log = std.log.scoped(.@"http.mfr");

const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const sort = @import("../sort.zig");
const slimselect = @import("slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
