db: *const DB,
idx: ?Manufacturer.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),
additional_names: std.StringArrayHashMapUnmanaged(Field_Data),
relations: std.StringArrayHashMapUnmanaged(Relation_Data),

add_another: bool = false,
was_valid: bool = true,
valid: bool = true,
changes_applied: bool = false,
names_changed: bool = false,
created_idx: ?Manufacturer.Index = null,

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

pub const Relation_Data = struct {
    other: Field_Data = .{},
    kind: Field_Data = .{},
    year: Field_Data = .{},
    valid: bool = true,
    err: []const u8 = "",

    pub fn fields_processed(self: Relation_Data) u2 {
        var result: u2 = 0;
        if (self.other.processed) result += 1;
        if (self.kind.processed) result += 1;
        if (self.year.processed) result += 1;
        return result;
    }
};

const Transaction = @This();

pub fn init_empty(db: *const DB) Transaction {
    return .{
        .db = db,
        .idx = null,
        .fields = .{
            .id = .{},
            .full_name = .{},
            .country = .{},
            .founded_year = .{},
            .suspended_year = .{},
            .notes = .{},
            .website = .{},
            .wiki = .{},
        },
        .additional_names = .{},
        .relations = .{},
    };
}

pub fn init_idx(db: *const DB, idx: Manufacturer.Index) !Transaction {
    const mfr = Manufacturer.get(db, idx);

    var additional_names: std.StringArrayHashMapUnmanaged(Field_Data) = .{};
    try additional_names.ensureTotalCapacity(http.temp(), mfr.additional_names.items.len);

    for (0.., mfr.additional_names.items) |i, name| {
        const key = try http.tprint("{d}", .{ i });
        additional_names.putAssumeCapacity(key, try Field_Data.init(db, name));
    }

    const sorted_relations = try common.get_sorted_relations(db, idx);
    var relations: std.StringArrayHashMapUnmanaged(Relation_Data) = .{};
    try relations.ensureTotalCapacity(http.temp(), sorted_relations.items.len);

    for (0.., sorted_relations.items) |i, relation| {
        const key = try http.tprint("{d}", .{ i });
        relations.putAssumeCapacity(key, .{
            .other = try Field_Data.init(db, relation.other),
            .kind = try Field_Data.init(db, relation.kind),
            .year = try Field_Data.init(db, relation.year),
        });
    }

    return .{
        .db = db,
        .idx = idx,
        .fields = try Field_Data.init_fields(Field, db, mfr),
        .additional_names = additional_names,
        .relations = relations,
    };
}

pub fn process_query_params(self: *Transaction, req: *http.Request) !void {
    var iter = req.query_iterator();
    while (try iter.next()) |param| {
        try self.process_param(param);
    }
}

pub fn process_form_params(self: *Transaction, req: *http.Request) !void {
    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        try self.process_param(param);
    }
}

pub fn process_param(self: *Transaction, param: Query_Param) !void {
    if (!try self.maybe_process_param(param)) {
        log.warn("Unrecognized parameter: {s}", .{ param.name });
        return error.BadRequest;
    }
}

pub fn maybe_process_param(self: *Transaction, param: Query_Param) !bool {
    if (std.mem.eql(u8, param.name, "invalid")) {
        self.was_valid = false;
        return true;
    }

    if (std.mem.eql(u8, param.name, "another")) {
        self.add_another = true;
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "additional_name_order")) {
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "additional_name")) {
        const index_str = param.name["additional_name".len..];
        const value = try trim(param.value);

        const gop = try self.additional_names.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.set_processed(value, self.idx == null);
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "relation_order")) {
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "relation_kind")) {
        const index_str = param.name["relation_kind".len..];
        const value = try trim(param.value);

        const gop = try self.relations.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.kind.set_processed(value, self.idx == null);
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "relation_other")) {
        const index_str = param.name["relation_other".len..];
        const value = try trim(param.value);

        const gop = try self.relations.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.other.set_processed(value, self.idx == null);
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "relation_year")) {
        const index_str = param.name["relation_year".len..];
        const value = try trim(param.value);

        const gop = try self.relations.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.year.set_processed(value, self.idx == null);
        return true;
    }

    switch (std.meta.stringToEnum(Field, param.name) orelse return false) {
        inline else => |field| {
            const value = try trim(param.value);
            @field(self.fields, @tagName(field)).set_processed(value, self.idx == null);
            return true;
        }
    }
}

fn trim(value: ?[]const u8) ![]const u8 {
    return try http.temp().dupe(u8, std.mem.trim(u8, value orelse "", &std.ascii.whitespace));
}

pub fn validate(self: *Transaction) !void {
    const additional_names = self.additional_names.values();
    try self.validate_name(&self.fields.id, .id, additional_names);
    try self.validate_name(&self.fields.full_name, .full_name, additional_names);
    for (1.., additional_names) |i, *data| {
        try self.validate_name(data, null, additional_names[i..]);
    }

    try self.validate_year(&self.fields.founded_year);
    try self.validate_year(&self.fields.suspended_year);

    for (self.relations.keys(), self.relations.values()) |relation_index, *relation| {
        try self.validate_relation(relation_index, relation);
    }
}

fn validate_year(self: *Transaction, data: *Field_Data) !void {
    if (data.future.len == 0) return;

    _ = std.fmt.parseInt(u16, data.future, 10) catch {
        log.debug("Invalid Year: {s}", .{ data.future });
        data.err = try http.tprint("'{s}' is not a valid year!", .{ data.future });
        data.valid = false;
        self.valid = false;
    };
}

fn validate_name(self: *Transaction, data: *Field_Data, field: ?Field, additional_names: []Field_Data) !void {
    if (data.is_changed()) {
        self.names_changed = true;
    }

    if (field == .id) {
        if (!DB.is_valid_id(data.future)) {
            log.debug("Invalid ID: {s}", .{ data.future });
            data.err = "ID may not be empty or '_', or contain '/'";
            data.valid = false;
            self.valid = false;
            return;
        }

        // check and remove duplicate in full name field
        if (std.ascii.eqlIgnoreCase(data.future, self.fields.full_name.future)) {
            self.fields.full_name.future = "";
            self.names_changed = true;
        }
    } else if (data.future.len == 0) return;

    if (Manufacturer.maybe_lookup(self.db, data.future)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx) {
            log.debug("Invalid ID (in use): {s}", .{ data.future });
            const existing_id = Manufacturer.get_id(self.db, existing_idx);
            data.err = try http.tprint("In use by <a href=\"/mfr:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
            data.valid = false;
            self.valid = false;
            return;
        }
    }

    // check and remove duplicates in additional_names
    for (additional_names) |*additional_name| {
        if (std.ascii.eqlIgnoreCase(data.future, additional_name.future)) {
            additional_name.future = "";
            self.names_changed = true;
        }
    }
}

fn validate_relation(self: *Transaction, index_str: []const u8, relation: *Relation_Data) !void {
    const fields_processed = relation.fields_processed();
    if (fields_processed == 0) return;
    if (fields_processed != 3) {
        log.warn("Expected parameters relation_kind{s}, relation_other{s}, and relation_year{s}", .{
            index_str, index_str, index_str,
        });
        return error.BadRequest;
    }

    if (relation.other.future.len == 0) return;

    if (Manufacturer.maybe_lookup(self.db, relation.other.future)) |other_idx| {
        relation.other.future = Manufacturer.get_id(self.db, other_idx);
        if (self.idx == other_idx) {
            log.debug("Mfr can't have a relation with itself: {s}", .{ relation.other.future });
            relation.other.err = "Select a different manufacturer";
            relation.other.valid = false;
            relation.err = relation.other.err;
            relation.valid = false;
            self.valid = false;
        }
    } else {
        log.debug("Mfr not found: {s}", .{ relation.other.future });
        relation.other.err = "Manufacturer not found";
        relation.other.valid = false;
        relation.err = relation.other.err;
        relation.valid = false;
        self.valid = false;
    }

    if (null == std.meta.stringToEnum(Kind, relation.kind.future)) {
        log.debug("Invalid relation kind: {s}", .{ relation.kind.future });
        relation.kind.err = "Invalid relation type";
        relation.kind.valid = false;
        relation.err = relation.kind.err;
        relation.valid = false;
        self.valid = false;
    }

    try self.validate_year(&relation.year);
    if (!relation.year.valid) {
        relation.err = relation.year.err;
        relation.valid = false;
        self.valid = false;
    }
}

pub fn apply_changes(self: *Transaction, db: *DB) !void {
    if (!self.valid) return;

    const idx = self.idx orelse {
        const id_str = self.fields.id.future_opt() orelse {
            log.warn("ID not specified", .{});
            return error.BadRequest;
        };
        
        const idx = try Manufacturer.lookup_or_create(db, id_str);
        try Manufacturer.set_full_name(db, idx, self.fields.full_name.future_opt());
        try Manufacturer.set_country(db, idx, self.fields.country.future_opt());
        try Manufacturer.set_founded_year(db, idx, self.fields.founded_year.future_opt_int(u16));
        try Manufacturer.set_suspended_year(db, idx, self.fields.suspended_year.future_opt_int(u16));
        try Manufacturer.set_notes(db, idx, self.fields.notes.future_opt());
        try Manufacturer.set_website(db, idx, self.fields.website.future_opt());
        try Manufacturer.set_wiki(db, idx, self.fields.wiki.future_opt());

        for (self.additional_names.values()) |name_data| {
            if (name_data.future_opt()) |name| {
                try Manufacturer.add_additional_names(db, idx, &.{ name });
            }
        }

        for (self.relations.values()) |relation| {
            if (relation.other.future_opt()) |other| {
                const other_idx = Manufacturer.maybe_lookup(db, other).?;
                const kind = relation.kind.future_enum(Kind);
                const year = relation.year.future_opt_int(u16);
                const relation_idx = try Manufacturer.Relation.lookup_or_create(db, idx, other_idx, kind, year);
                try Manufacturer.Relation.set_ordering(db, idx, relation_idx, 0xFFFF);
            }
        }

        self.changes_applied = true;
        self.created_idx = idx;
        return;
    };

    if (self.names_changed) {
        try Manufacturer.set_full_name(db, idx, null);
        for (self.additional_names.values()) |name_data| {
            if (name_data.current_opt()) |name| {
                try Manufacturer.remove_additional_name(db, idx, name);
            }
        }

        try Manufacturer.set_id(db, idx, self.fields.id.future);
        try Manufacturer.set_full_name(db, idx, self.fields.full_name.future_opt());
        for (self.additional_names.values()) |name_data| {
            if (name_data.future_opt()) |name| {
                try Manufacturer.add_additional_names(db, idx, &.{ name });
            }
        }
        self.changes_applied = true;
    }

    if (self.fields.country.changed()) |country| {
        try Manufacturer.set_country(db, idx, country.future_opt());
        self.changes_applied = true;
    }
    if (self.fields.founded_year.changed()) |year| {
        try Manufacturer.set_founded_year(db, idx, year.future_opt_int(u16));
        self.changes_applied = true;
    }
    if (self.fields.suspended_year.changed()) |year| {
        try Manufacturer.set_suspended_year(db, idx, year.future_opt_int(u16));
        self.changes_applied = true;
    }
    if (self.fields.notes.changed()) |notes| {
        try Manufacturer.set_notes(db, idx, notes.future_opt());
        self.changes_applied = true;
    }
    if (self.fields.website.changed()) |website| {
        try Manufacturer.set_website(db, idx, website.future_opt());
        self.changes_applied = true;
    }
    if (self.fields.wiki.changed()) |wiki| {
        try Manufacturer.set_wiki(db, idx, wiki.future_opt());
        self.changes_applied = true;
    }

    for (self.relations.values()) |relation| {
        if (relation.other.is_removed()) {
            const other_idx = Manufacturer.maybe_lookup(db, relation.other.current).?;
            const kind = relation.kind.current_enum(Kind);
            const year = relation.year.current_opt_int(u16);
            try Manufacturer.Relation.maybe_remove(db, idx, other_idx, kind, year);
            self.changes_applied = true;
        } else if (relation.other.future.len > 0) {
            const relation_idx = if (relation.other.current.len > 0) relation_idx: {
                const other_idx = Manufacturer.maybe_lookup(db, relation.other.current).?;
                const kind = relation.kind.current_enum(Kind);
                const year = relation.year.current_opt_int(u16);
                break :relation_idx try Manufacturer.Relation.lookup_or_create(db, idx, other_idx, kind, year);
            } else relation_idx: {
                self.changes_applied = true;
                const other_idx = Manufacturer.maybe_lookup(db, relation.other.future).?;
                const kind = relation.kind.future_enum(Kind);
                const year = relation.year.future_opt_int(u16);
                const relation_idx = try Manufacturer.Relation.lookup_or_create(db, idx, other_idx, kind, year);
                try Manufacturer.Relation.set_ordering(db, idx, relation_idx, 0xFFFF);
                break :relation_idx relation_idx;
            };

            if (Manufacturer.Relation.get_source(db, relation_idx) == idx) {
                if (relation.other.changed()) |other| {
                    const other_idx = Manufacturer.maybe_lookup(db, other.future).?;
                    try Manufacturer.Relation.set_target(db, relation_idx, other_idx);
                    self.changes_applied = true;
                }

                if (relation.kind.changed()) |kind| {
                    try Manufacturer.Relation.set_kind(db, relation_idx, kind.future_enum(Kind));
                    self.changes_applied = true;
                }

            } else if (Manufacturer.Relation.get_target(db, relation_idx) == idx) {
                if (relation.other.changed()) |other| {
                    const other_idx = Manufacturer.maybe_lookup(db, other.future).?;
                    try Manufacturer.Relation.set_source(db, relation_idx, other_idx);
                    self.changes_applied = true;
                }
                
                if (relation.kind.changed()) |kind| {
                    try Manufacturer.Relation.set_kind(db, relation_idx, kind.future_enum(Kind).inverse());
                    self.changes_applied = true;
                }

            } else unreachable;

            if (relation.year.changed()) |year| {
                try Manufacturer.Relation.set_year(db, relation_idx, year.future_opt_int(u16));
                self.changes_applied = true;
            }
        }
    }
}

pub fn get_post_prefix(db: *const DB, maybe_idx: ?Manufacturer.Index) ![]const u8 {
    if (maybe_idx) |idx| {
        const id = Manufacturer.get_id(db, idx);
        return try http.tprint("/mfr:{}", .{ http.fmtForUrl(id) });
    }
    return "/mfr";
}


const Render_Options = struct {
    target: union (enum) {
        add,
        edit,
        field: Field,
        additional_name: []const u8,
        relation: []const u8,
    },
    rnd: ?*std.rand.Xoshiro256,
};

pub fn render_results(self: Transaction, session: ?Session, req: *http.Request, options: Render_Options) !void {
    const post_prefix = try get_post_prefix(self.db, self.created_idx orelse self.idx);

    if (self.changes_applied) {
        if (self.created_idx != null) {
            if (self.add_another) {
                try req.redirect(try http.tprint("/mfr/add{s}", .{ req.hx_current_query() }), .see_other);
            } else {
                try req.redirect(post_prefix, .see_other);
            }
            return;
        } else if (self.fields.id.is_changed()) {
            try req.redirect(try http.tprint("{s}?edit", .{ post_prefix }), .see_other);
            return;
        }
    }

    if (self.was_valid != self.valid) {
        try req.add_response_header("hx-trigger", "revalidate");
    }

    const obj = Field_Data.future_obj(Field, self.fields);

    switch (options.target) {
        .add, .edit => {
            const additional_names = try http.temp().alloc([]const u8, self.additional_names.count());
            for (additional_names, self.additional_names.values()) |*rel, data| {
                rel.* = data.future;
            }

            const relations = try http.temp().alloc(common.Relation, self.relations.count());
            for (relations, self.relations.values()) |*rel, data| {
                const kind = data.kind.current_enum(Kind);
                rel.* = .{
                    .db_index = null,
                    .is_inverted = false,
                    .kind = kind,
                    .kind_str = kind.display(),
                    .other = data.other.future,
                    .year = data.year.future_opt_int(u16),
                    .ordering = 0,
                };
            }

            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .show_years = obj.founded_year.len > 0 or obj.suspended_year.len > 0,
                .title = self.fields.full_name.future_opt() orelse self.fields.id.future,
                .additional_names = additional_names,
                .relations = relations,
                .post_prefix = post_prefix,
                .cancel_url = "/mfr",
                .country_search_url = "/mfr/countries",
            };

            return switch (options.target) {
                .add => try req.render("mfr/add.zk", render_data, .{}),
                .edit => try req.render("mfr/edit.zk", render_data, .{}),
                else => unreachable,
            };
        },
        else => {},
    }

    inline for (comptime std.enums.values(Field)) |field| {
        const is_target = switch (options.target) {
            .field => |target_field| field == target_field,
            else => false,
        };

        const data = @field(self.fields, @tagName(field));
        if (is_target or data.is_changed()) {
            const render_data = .{
                .validating = true,
                .saved = self.changes_applied,
                .valid = data.valid,
                .err = data.err,
                .swap_oob = !is_target,
                .obj = obj,
                .post_prefix = post_prefix,
                .country_search_url = "/mfr/countries",
            };
            switch (field) {
                .id => try req.render("common/post_id.zk", render_data, .{}),
                .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
                .country => try req.render("common/post_country.zk", render_data, .{}),
                .founded_year => try req.render("common/post_founded_year.zk", render_data, .{}),
                .suspended_year => try req.render("common/post_suspended_year.zk", render_data, .{}),
                .notes => try req.render("common/post_notes.zk", render_data, .{}),
                .website => try req.render("common/post_website.zk", render_data, .{}),
                .wiki => try req.render("common/post_wiki.zk", render_data, .{}),
            }
        }
    }

    try additional_names_util.render_results(req, self, .{
        .rnd = options.rnd,
        .target_index = switch (options.target) {
            .additional_name => |target_index| target_index,
            else => null,
        },
        .post_prefix = post_prefix,
    });

    var relation_index: usize = 0;
    for (self.relations.keys(), self.relations.values()) |index_str, data| {
        const is_target = switch (options.target) {
            .relation => |target_index| std.mem.eql(u8, index_str, target_index),
            else => false,
        };
        const is_changed = data.kind.is_changed() or data.other.is_changed() or data.year.is_changed();

        const is_index_changed = if (self.idx != null and index_str.len > 0) is_index_changed: {
            const old_relation_index = try std.fmt.parseInt(u16, index_str, 10);
            break :is_index_changed relation_index != old_relation_index;
        } else false;
        
        if (!is_target and !is_changed and !is_index_changed) {
            relation_index += 1;
            continue;
        }
        
        var new_index_buf: [32]u8 = undefined;
        var new_index: []const u8 = if (is_index_changed) try http.tprint("{d}", .{ relation_index }) else index_str;
        var is_placeholder = true;

        if (index_str.len > 0) {
            if (data.other.future.len == 0) {
                if (is_target) {
                    _ = try req.response();
                } else {
                    try req.render("mfr/post_relation.zk", .{
                        .index = index_str,
                        .swap_oob = "delete",
                    }, .{});
                }
                continue;
            }
            relation_index += 1;
            is_placeholder = false;
        } else if (data.other.future.len > 0 and data.valid) {
            if (options.rnd) |rnd| {
                var buf: [16]u8 = undefined;
                rnd.fill(&buf);
                const Base64 = std.base64.url_safe_no_pad.Encoder;
                new_index = Base64.encode(&new_index_buf, &buf);
            } else {
                new_index = try std.fmt.bufPrint(&new_index_buf, "{d}", .{ self.relations.count() - 1 });
            }
            is_placeholder = false;
        }

        const render_data = .{
            .saved = self.changes_applied and is_changed,
            .valid = data.valid,
            .err = data.err,
            .post_prefix = post_prefix,
            .index = if (is_placeholder) null else new_index,
            .swap_oob = if (is_target) null else try http.tprint("outerHTML:#relation{s}", .{ index_str }),

            .kind = data.kind.future,
            .kind_str = if (data.kind.future_opt_enum(Kind)) |kind| kind.display() else null,
            .err_kind = !data.kind.valid,

            .other = data.other.future,
            .err_other = !data.other.valid,

            .year = data.year.future,
            .err_year = !data.year.valid,
        };

        if (is_placeholder) {
            try req.render("mfr/post_relation_placeholder.zk", render_data, .{});
        } else {
            try req.render("mfr/post_relation.zk", render_data, .{});
            if (index_str.len == 0) {
                try req.render("mfr/post_relation_placeholder.zk", .{
                    .post_prefix = post_prefix,
                }, .{});
            }
        }
    }
}

const log = std.log.scoped(.@"http.mfr");

const additional_names_util = @import("../additional_names_util.zig");
const Kind = Manufacturer.Relation.Kind;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const common = @import("../mfr.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
