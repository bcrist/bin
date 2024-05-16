pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = db.mfr_lookup.get(requested_mfr_name.?) orelse {
        if (try req.has_query_param("edit")) {
            try add.get(session, req);
        } else {
            try list.get(session, req, db);
        }
        return;
    };
    const mfr = db.mfrs.get(@intFromEnum(idx));

    if (!std.mem.eql(u8, requested_mfr_name.?, mfr.id)) {
        req.response_status = .moved_permanently;
        try req.add_response_header("Location", try http.tprint("/mfr:{s}", .{mfr.id}));
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

        pub fn post(req: *http.Request, db: *const DB) !void {
            var path_iter = req.path_iterator();
            _ = path_iter.next(); // /mfr
            const mode_str = path_iter.next() orelse return error.BadRequest;
            const mode = std.meta.stringToEnum(Validate_Mode, mode_str) orelse return error.BadRequest;

            var was_valid = true;
            var valid = true;
            var message: []const u8 = "";
            var mfr = Manufacturer.init_empty("", 0);

            var iter = try req.form_iterator();
            while (try iter.next()) |param| {
                if (std.mem.eql(u8, param.name, "invalid")) {
                    was_valid = false;
                    continue;
                }
                const field = std.meta.stringToEnum(Validate_Mode, param.name) orelse return error.BadRequest;
                const str_value = try http.temp().dupe(u8, param.value orelse "");
                switch (field) {
                    .add => return error.BadRequest,
                    .id => mfr.id = try validate_name(str_value, db, null, .id, &valid, &message),
                    .full_name => mfr.full_name = try validate_name(str_value, db, null, .full_name, &valid, &message),
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

pub const edit = struct {
    const Field = enum {
        id,
        full_name,
        country,
        founded_year,
        suspended_year,
        notes,
        website,
        wiki,
    };

     pub fn post(req: *http.Request, db: *DB) !void {
        const requested_mfr_name = try req.get_path_param("mfr");
        const idx = db.mfr_lookup.get(requested_mfr_name.?) orelse return;
        var mfr = db.mfrs.get(@intFromEnum(idx));
        const post_prefix = try http.tprint("/mfr:{s}", .{ mfr.id });

        var path_iter = req.path_iterator();
        _ = path_iter.next(); // /mfr:*
        const field_str = path_iter.next() orelse return error.BadRequest;
        const field = std.meta.stringToEnum(Field, field_str) orelse return error.BadRequest;

        var valid = true;
        var message: []const u8 = "";

        var iter = try req.form_iterator();
        while (try iter.next()) |param| {
            const str_value = param.value orelse "";
            if (!std.mem.eql(u8, param.name, field_str)) continue;
            switch (field) {
                .id => {
                    mfr.id = try validate_name(str_value, db, idx, .id, &valid, &message);
                    if (valid and try Manufacturer.set_id(db, idx, mfr.id)) {
                        try req.add_response_header("HX-Location", try http.tprint("/mfr:{s}?edit", .{ mfr.id }));
                    }
                },
                .full_name => {
                    const full_name = try validate_name(str_value, db, idx, .full_name, &valid, &message);
                    mfr.full_name = if (full_name.len == 0) null else full_name;
                    if (valid) {
                        try Manufacturer.set_full_name(db, idx, mfr.full_name);
                    }
                },
                .country => {
                    mfr.country = str_value;
                    if (valid) {
                        const maybe_country: ?[]const u8 = if (str_value.len == 0) null else str_value;
                        try Manufacturer.set_country(db, idx, maybe_country);
                    }
                },
                .founded_year => {
                    mfr.founded_year = try validate_year(str_value, &valid, &message);
                    if (valid) {
                        try Manufacturer.set_founded_year(db, idx, mfr.founded_year);
                    }
                },
                .suspended_year => {
                    mfr.suspended_year = try validate_year(str_value, &valid, &message);
                    if (valid) {
                        try Manufacturer.set_suspended_year(db, idx, mfr.suspended_year);
                    }
                },
                .notes => {
                    mfr.notes = str_value;
                    if (valid) {
                        const maybe_str: ?[]const u8 = if (str_value.len == 0) null else str_value;
                        try Manufacturer.set_notes(db, idx, maybe_str);
                    }
                },
                .website => {
                    mfr.website = str_value;
                    if (valid) {
                        const maybe_str: ?[]const u8 = if (str_value.len == 0) null else str_value;
                        try Manufacturer.set_website(db, idx, maybe_str);
                    }
                },
                .wiki => {
                    mfr.wiki = str_value;
                    if (valid) {
                        const maybe_str: ?[]const u8 = if (str_value.len == 0) null else str_value;
                        try Manufacturer.set_wiki(db, idx, maybe_str);
                    }
                },
            }
            break;
        }

        const render_data = .{
            .validating = true,
            .valid = valid,
            .saved = valid,
            .err = message,
            .mfr = mfr,
            .post_prefix = post_prefix,
        };

        switch (field) {
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

    pub const additional_name = struct {
        pub fn post(req: *http.Request, db: *DB) !void {
            const requested_mfr_name = try req.get_path_param("mfr");
            const idx = db.mfr_lookup.get(requested_mfr_name.?) orelse return;
            const mfr_id = db.mfrs.items(.id)[@intFromEnum(idx)];
            const name_list = &db.mfrs.items(.additional_names)[@intFromEnum(idx)];
            const post_prefix = try http.tprint("/mfr:{s}", .{ mfr_id });

            var valid = true;
            var message: []const u8 = "";

            var iter = try req.form_iterator();
            while (try iter.next()) |param| {
                const str_value = param.value orelse "";

                const expected_prefix = "additional_name";
                if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
                const index_str = param.name[expected_prefix.len..];
                const maybe_index: ?usize = if (std.mem.eql(u8, index_str, "_new")) null else std.fmt.parseUnsigned(usize, index_str, 10) catch return error.BadRequest;

                const new_name = try validate_name(str_value, db, idx, .{ .additional_name = maybe_index }, &valid, &message);

                if (new_name.len == 0) {
                    if (maybe_index) |index| {
                        if (valid) {
                            try Manufacturer.remove_additional_name(db, idx, name_list.items[index]);
                        }
                        try req.respond("");
                    } else {
                        try req.render("mfr/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
                    }
                } else {
                    if (maybe_index) |index| {
                        if (valid) {
                            try Manufacturer.rename_additional_name(db, idx, name_list.items[index], new_name);
                        }
                        try req.render("mfr/post_additional_name.zk", .{
                            .valid = valid,
                            .saved = valid,
                            .err = message,
                            .post_prefix = post_prefix,
                            .index = index,
                            .name = new_name,
                        }, .{});
                    } else {
                        if (valid) {
                            try Manufacturer.add_additional_names(db, idx, &.{ new_name });
                            try req.render("mfr/post_additional_name.zk", .{
                                .valid = true,
                                .saved = true,
                                .post_prefix = post_prefix,
                                .index = name_list.items.len - 1,
                                .name = new_name,
                            }, .{});
                            try req.render("mfr/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
                        } else {
                            try req.render("mfr/post_additional_name_placeholder.zk", .{
                                .valid = false,
                                .err = message,
                                .post_prefix = post_prefix,
                                .name = new_name,
                            }, .{});
                        }
                    }
                }
            }
        }
    };

    pub const additional_names = struct {
        pub fn post(req: *http.Request, db: *DB) !void {
            const requested_mfr_name = try req.get_path_param("mfr");
            const idx = db.mfr_lookup.get(requested_mfr_name.?) orelse return;
            const mfr_id = db.mfrs.items(.id)[@intFromEnum(idx)];
            const name_list = &db.mfrs.items(.additional_names)[@intFromEnum(idx)];
            const post_prefix = try http.tprint("/mfr:{s}", .{ mfr_id });

            var new_list = try std.ArrayList([]const u8).initCapacity(http.temp(), name_list.items.len);
            var apply_changes = true;

            var iter = try req.form_iterator();
            while (try iter.next()) |param| {
                const expected_prefix = "additional_name";
                if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
                const index_str = param.name[expected_prefix.len..];
                if (std.mem.eql(u8, index_str, "_new")) continue;
                const index = std.fmt.parseUnsigned(usize, index_str, 10) catch {
                    apply_changes = false;
                    break;
                };
                if (index >= name_list.items.len) {
                    apply_changes = false;
                }

                try new_list.append(name_list.items[index]);
            }

            if (apply_changes and new_list.items.len == name_list.items.len) {
                @memcpy(name_list.items, new_list.items);
            }

            for (0.., name_list.items) |i, name| {
                try req.render("mfr/post_additional_name.zk", .{
                    .valid = true,
                    .post_prefix = post_prefix,
                    .index = i,
                    .name = name,
                }, .{});
            }
            try req.render("mfr/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
        }
    };
};

const Name_Field = union (enum) {
    id,
    full_name,
    additional_name: ?usize,
};
fn validate_name(name: []const u8, db: *const DB, for_mfr: ?Manufacturer.Index, for_field: Name_Field, valid: *bool, message: *[]const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, name, &std.ascii.whitespace);
    if (for_field == .id) {
        if (trimmed.len == 0) {
            valid.* = false;
            message.* = "Required";
            return trimmed;
        }
        if (std.mem.indexOfAny(u8, trimmed, &std.ascii.whitespace) != null) {
            valid.* = false;
            message.* = "Cannot contain whitespace";
            return trimmed;
        }
    }

    if (db.mfr_lookup.get(trimmed)) |idx| {
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

        // TODO Create a /mfr:*/merge:* endpoint?
        valid.* = false;
        message.* = try http.tprint("In use by <a href=\"/mfr:{s}\" target=\"_blank\">{s}</a>", .{ id, id });
        return trimmed;
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
        message.* = try http.tprint("'{s}' is not a valid year!", .{ str_value });
        return null;
    };
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
        .edit => try http.tprint("/mfr:{s}", .{mfr.id}),
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
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
