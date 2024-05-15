pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const requested = try req.get_path_param("mfr");
    const idx = db.mfr_lookup.get(requested.?) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const mfr = db.mfrs.get(@intFromEnum(idx));

    if (!std.mem.eql(u8, requested.?, mfr.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try std.fmt.allocPrint(http.temp(), "/mfr:{s}", .{mfr.id}));
        try req.respond("");
        return;
    }

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

    try render_mfr(session, req, mfr, relations.items, if (try req.has_query_param("edit")) .edit else .info);
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
    pub fn get(session: ?Session, req: *http.Request) !void {
        const id = (try req.get_path_param("mfr")) orelse "";
        const now = std.time.milliTimestamp();
        const mfr = Manufacturer.init_empty(id, now);
        try render_mfr(session, req, mfr, &.{}, .add);
    }

    // TODO post()

    pub const validate = struct {
        const Validate_Mode = enum {
            add,
            id,
            full_name,
            country,
            founded_year,
            suspended_year,
            notes,
            website,
            wiki,
        };

        fn validate_name(name: []const u8, db: *const DB, allow_empty: bool, allow_whitespace: bool, valid: *bool, message: *[]const u8) ![]const u8 {
            const trimmed = std.mem.trim(u8, name, &std.ascii.whitespace);
            if (trimmed.len == 0 and !allow_empty) {
                valid.* = false;
                message.* = "Required";
            } else if (!allow_whitespace and std.mem.indexOfAny(u8, trimmed, &std.ascii.whitespace) != null) {
                valid.* = false;
                message.* = "Cannot contain whitespace";
            } else if (db.mfr_lookup.get(trimmed)) |idx| {
                const id = db.mfrs.items(.id)[@intFromEnum(idx)];
                valid.* = false;
                message.* = try std.fmt.allocPrint(http.temp(), "In use by <a href=\"/mfr:{s}\" target=\"_blank\">{s}</a>", .{ id, id });
            }
            return trimmed;
        }

        fn validate_year(str_value: []const u8, valid: *bool, message: *[]const u8) !?u16 {
            const trimmed = std.mem.trim(u8, str_value, &std.ascii.whitespace);
            if (trimmed.len == 0) {
                return null;
            }
            return std.fmt.parseInt(u16, str_value, 10) catch {
                valid.* = false;
                message.* = try std.fmt.allocPrint(http.temp(), "'{s}' is not a valid year!", .{ str_value });
                return null;
            };
        }

        pub fn post(req: *http.Request, db: *const DB) !void {
            var path_iter = req.path_iterator();
            _ = path_iter.next(); // /mfr
            const mode_str = path_iter.next() orelse return error.BadRequest;
            const mode = std.meta.stringToEnum(Validate_Mode, mode_str) orelse return error.BadRequest;

            var body_data = try std.ArrayList(u8).initCapacity(http.temp(), 4096);
            var reader = try req.req.reader();
            try reader.readAllArrayList(&body_data, 2 * 1024 * 1024);

            var was_valid = true;
            var valid = true;
            var message: []const u8 = "";
            var mfr = Manufacturer.init_empty("", 0);

            // TODO req.form_iterator(http.temp())
            var iter = http.query_iterator(http.temp(), body_data.items);
            while (try iter.next()) |param| {
                if (std.mem.eql(u8, param.name, "invalid")) {
                    was_valid = false;
                    continue;
                }
                const field = std.meta.stringToEnum(Validate_Mode, param.name) orelse return error.BadRequest;
                const str_value = try http.temp().dupe(u8, param.value orelse "");
                switch (field) {
                    .add => return error.BadRequest,
                    .id => mfr.id = try validate_name(str_value, db, false, false, &valid, &message),
                    .full_name => mfr.full_name = try validate_name(str_value, db, true, true, &valid, &message),
                    .country => mfr.country = str_value,
                    .founded_year => mfr.founded_year = try validate_year(str_value, &valid, &message),
                    .suspended_year => mfr.suspended_year = try validate_year(str_value, &valid, &message),
                    .notes => mfr.notes = str_value,
                    .website => mfr.website = str_value,
                    .wiki => mfr.wiki = str_value,
                }
            }

            if (mode != .add and was_valid != valid) {
                try req.add_response_header("hx-trigger", "revalidate");
            }

            const render_data = .{
                .validating = true,
                .valid = valid,
                .err = message,
                .mfr = mfr,
                .post_prefix = "/mfr",
            };

            switch (mode) {
                .add => try req.render("_add_button.zk", render_data, .{}),
                .id => try req.render("mfr/post_id.zk", render_data, .{}),
                .full_name => try req.render("mfr/post_full_name.zk", render_data, .{}),
                .country => try req.render("mfr/post_country.zk", render_data, .{}),
                .founded_year => try req.render("mfr/post_founded_year.zk", render_data, .{}),
                .suspended_year => try req.render("mfr/post_suspended_year.zk", render_data, .{}),
                .notes => try req.render("mfr/post_notes.zk", render_data, .{}),
                .website => try req.render("mfr/post_website.zk", render_data, .{}),
                .wiki => try req.render("mfr/post_wiki.zk", render_data, .{}),
            }
        }
    };
};

const Relation = struct {
    kind: []const u8,
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

fn render_mfr(session: ?Session, req: *http.Request, mfr: Manufacturer, relations: []const Relation, mode: Render_Mode) !void {
    if (mode != .info) try Session.redirect_if_missing(req, session);

    const tz = try tempora.tzdb.timezone(if (session) |s| s.timezone else "GMT");

    const created_dto = tempora.Date_Time.With_Offset.from_timestamp_ms(mfr.created_timestamp_ms, tz);
    const modified_dto = tempora.Date_Time.With_Offset.from_timestamp_ms(mfr.modified_timestamp_ms, tz);

    const Context = struct {
        pub const created = tempora.Date_Time.With_Offset.fmt_sql;
        pub const modified = tempora.Date_Time.With_Offset.fmt_sql;
    };

    const post_prefix = switch (mode) {
        .info => "",
        .edit => try std.fmt.allocPrint(http.temp(), "/mfr:{s}", .{mfr.id}),
        .add => "/mfr",
    };

    const data = .{
        .mode = mode,
        .post_prefix = post_prefix,
        .title = mfr.full_name orelse mfr.id,
        .mfr = mfr,
        .session = session,
        .full_name = mfr.full_name orelse mfr.id,
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
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
