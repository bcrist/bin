db: *const DB,
idx: ?Package.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),
parent_mfr: Field_Data,
additional_names: std.StringArrayHashMapUnmanaged(Field_Data),

add_another: bool = false,
was_valid: bool = true,
valid: bool = true,
changes_applied: bool = false,
names_changed: bool = false,
created_idx: ?Package.Index = null,

pub const Field = enum {
    mfr,
    id,
    full_name,
    parent,
    notes,
};

const Transaction = @This();

pub fn init_empty(db: *const DB) Transaction {
        return .{
        .db = db,
        .idx = null,
        .fields = .{
            .mfr = .{},
            .id = .{},
            .full_name = .{},
            .parent = .{},
            .notes = .{},
        },
        .parent_mfr = .{},
        .additional_names = .{},
    };
}

pub fn init_idx(db: *const DB, idx: Package.Index) !Transaction {
    const pkg = Package.get(db, idx);

    const parent_mfr: Field_Data = if (pkg.parent) |parent_idx|
        try Field_Data.init(db, Package.get_mfr(db, parent_idx)) else .{};

    var additional_names: std.StringArrayHashMapUnmanaged(Field_Data) = .{};
    try additional_names.ensureTotalCapacity(http.temp(), pkg.additional_names.items.len);

    for (0.., pkg.additional_names.items) |i, name| {
        const key = try http.tprint("{d}", .{ i });
        additional_names.putAssumeCapacity(key, try Field_Data.init(db, name));
    }

    return .{
        .db = db,
        .idx = idx,
        .fields = try Field_Data.init_fields(Field, db, pkg),
        .parent_mfr = parent_mfr,
        .additional_names = additional_names,
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

    if (std.mem.eql(u8, param.name, "parent_mfr")) {
        const value = try trim(param.value);
        self.parent_mfr.set_processed(value, self.idx == null);
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
    if (self.fields.mfr.is_changed()) {
        self.names_changed = true;
    }
    try self.validate_mfr(&self.fields.mfr);
    try self.validate_id();
    try self.validate_mfr(&self.parent_mfr);
    try self.validate_parent();
    try self.validate_full_name();

    const additional_names = self.additional_names.values();
    for (0.., additional_names) |i, *data| {
        try self.validate_additional_name(data, additional_names[0..i]);
    }
}

fn validate_mfr(self: *Transaction, data: *Field_Data) !void {
    if (data.future.len == 0) return;

    const mfr_idx = Manufacturer.maybe_lookup(self.db, data.future) orelse {
        log.debug("Invalid manufacturer: {s}", .{ data.future });
        data.err = "Invalid manufacturer";
        data.valid = false;
        self.valid = false;
        return;
    };

    data.future = Manufacturer.get_id(self.db, mfr_idx);
}

fn validate_id(self: *Transaction) !void {
    if (self.fields.id.is_changed()) {
        self.names_changed = true;
    }

    if (!DB.is_valid_id(self.fields.id.future)) {
        log.debug("Invalid ID: {s}", .{ self.fields.id.future });
        self.fields.id.err = "ID may not be empty or '_', or contain '/'";
        self.fields.id.valid = false;
        self.valid = false;
        return;
    }

    try self.validate_name_not_in_use(&self.fields.id);
}

fn validate_parent(self: *Transaction) !void {
    if (self.fields.parent.future.len == 0) return;

    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.parent_mfr.future);

    const parent_idx = Package.maybe_lookup(self.db, mfr_idx, self.fields.parent.future) orelse {
        log.debug("Invalid parent package: {s}", .{ self.fields.parent.future });
        self.fields.parent.err = "Invalid package";
        self.fields.parent.valid = false;
        self.valid = false;
        return;
    };

    self.fields.parent.future = Package.get_id(self.db, parent_idx);

    if (self.idx) |idx| {
        if (Package.is_ancestor(self.db, parent_idx, idx)) {
            log.debug("Recursive package parent chain involving: {s}", .{ self.fields.parent.future });
            self.fields.parent.err = "Recursive packages are not allowed!";
            self.fields.parent.valid = false;
            self.valid = false;
            return;
        }
    }
}

fn validate_full_name(self: *Transaction) !void {
    if (self.fields.full_name.is_changed()) {
        self.names_changed = true;
    }

    if (self.fields.full_name.future.len == 0) return;

    if (std.ascii.eqlIgnoreCase(self.fields.id.future, self.fields.full_name.future)) {
        self.fields.full_name.future = "";
        self.names_changed = true;
        return;
    }

    try self.validate_name_not_in_use(&self.fields.full_name);
}

fn validate_additional_name(self: *Transaction, data: *Field_Data, prev_additional_names: []Field_Data) !void {
    if (data.is_changed()) {
        self.names_changed = true;
    }

    if (data.future.len == 0) return;

    if (std.ascii.eqlIgnoreCase(data.future, self.fields.id.future)) {
        data.future = "";
        self.names_changed = true;
        return;
    }

    if (std.ascii.eqlIgnoreCase(data.future, self.fields.full_name.future)) {
        data.future = "";
        self.names_changed = true;
        return;
    }

    for (prev_additional_names) |*additional_name| {
        if (std.ascii.eqlIgnoreCase(data.future, additional_name.future)) {
            data.future = "";
            self.names_changed = true;
            return;
        }
    }

    try self.validate_name_not_in_use(data);
}

fn validate_name_not_in_use(self: *Transaction, data: *Field_Data) !void {
    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.fields.mfr.future);

    if (Package.maybe_lookup(self.db, mfr_idx, data.future)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx.?) {
            log.debug("Invalid ID (in use): {s}", .{ data.future });
            const existing_id = Package.get_id(self.db, existing_idx);
            const maybe_existing_mfr_idx = Package.get_mfr(self.db, existing_idx);
            if (maybe_existing_mfr_idx) |existing_mfr_idx| {
                data.err = try http.tprint("In use by <a href=\"/mfr:{}/pkg:{}\" target=\"_blank\">{s}</a>", .{
                    http.fmtForUrl(Manufacturer.get_id(self.db, existing_mfr_idx)),
                    http.fmtForUrl(existing_id),
                    existing_id,
                });
            } else {
                data.err = try http.tprint("In use by <a href=\"/pkg:{}\" target=\"_blank\">{s}</a>", .{
                    http.fmtForUrl(existing_id),
                    existing_id,
                });
            }
            data.valid = false;
            self.valid = false;
        }
    }
}

pub fn apply_changes(self: *Transaction, db: *DB) !void {
    if (!self.valid) return;

    const idx = self.idx orelse {
        const id_str = self.fields.id.future_opt() orelse {
            log.warn("ID not specified", .{});
            return error.BadRequest;
        };

        const mfr_idx = Manufacturer.maybe_lookup(db, self.fields.mfr.future_opt());

        const idx = try Package.lookup_or_create(db, mfr_idx, id_str);
        try Package.set_full_name(db, idx, self.fields.full_name.future_opt());
        try Package.set_notes(db, idx, self.fields.notes.future_opt());
        
        if (self.fields.parent.future_opt()) |parent| {
            const parent_mfr_idx = Manufacturer.maybe_lookup(db, self.parent_mfr.future_opt());
            const parent_idx = Package.maybe_lookup(db, parent_mfr_idx, parent).?;
            try Package.set_parent(db, idx, parent_idx);
        }

        for (self.additional_names.values()) |name_data| {
            if (name_data.future_opt()) |name| {
                try Package.add_additional_names(db, idx, &.{ name });
            }
        }

        self.changes_applied = true;
        self.created_idx = idx;
        return;
    };

    if (self.names_changed) {
        try Package.set_full_name(db, idx, null);
        for (self.additional_names.values()) |name_data| {
            if (name_data.current_opt()) |name| {
                try Package.remove_additional_name(db, idx, name);
            }
        }

        const mfr_idx = Manufacturer.maybe_lookup(db, self.fields.mfr.future_opt());
        try Package.set_id(db, idx, mfr_idx, self.fields.id.future);

        try Package.set_full_name(db, idx, self.fields.full_name.future_opt());
        for (self.additional_names.values()) |name_data| {
            if (name_data.future_opt()) |name| {
                try Package.add_additional_names(db, idx, &.{ name });
            }
        }
        self.changes_applied = true;
    }

    if (self.fields.notes.changed()) |notes| {
        try Package.set_notes(db, idx, notes.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.parent.is_removed()) {
        try Package.set_parent(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.parent.future_opt()) |parent_id| {
        if (self.fields.parent.is_changed() or self.parent_mfr.is_changed()) {
            const parent_mfr_idx = Manufacturer.maybe_lookup(db, self.parent_mfr.future_opt());
            const parent_idx = Package.maybe_lookup(db, parent_mfr_idx, parent_id).?;
            try Package.set_parent(db, idx, parent_idx);
            self.changes_applied = true;
        }
    }
}

pub fn get_post_prefix(db: *const DB, maybe_idx: ?Package.Index) ![]const u8 {
    if (maybe_idx) |idx| {
        const id = Package.get_id(db, idx);
        if (Package.get_mfr(db, idx)) |mfr_idx| {
            const mfr_id = Manufacturer.get_id(db, mfr_idx);
            return try http.tprint("/mfr:{}/pkg:{}", .{ http.fmtForUrl(mfr_id), http.fmtForUrl(id) });
        } else {
            return try http.tprint("/pkg:{}", .{ http.fmtForUrl(id) });
        }
    }
    return "/pkg";
}

const Render_Options = struct {
    target: union (enum) {
        add,
        edit,
        field: Field,
        parent_mfr,
        additional_name: []const u8,
    },
    rnd: ?*std.rand.Xoshiro256,
};

pub fn render_results(self: Transaction, session: ?Session, req: *http.Request, options: Render_Options) !void {
    const post_prefix = try get_post_prefix(self.db, self.created_idx orelse self.idx);

    if (self.changes_applied) {
        if (self.created_idx != null) {
            if (self.add_another) {
                try req.redirect(try http.tprint("/pkg/add{s}", .{ req.hx_current_query() }), .see_other);
            } else {
                try req.redirect(post_prefix, .see_other);
            }
            return;
        } else if (self.fields.id.is_changed() or self.fields.mfr.is_changed()) {
            try req.redirect(try http.tprint("{s}?edit", .{ post_prefix }), .see_other);
            return;
        }
    }

    if (self.was_valid != self.valid) {
        try req.add_response_header("hx-trigger", "revalidate");
    }

    const obj: std.enums.EnumFieldStruct(Field, []const u8, null) = .{
        .id = self.fields.id.future,
        .full_name = self.fields.full_name.future,
        .notes = self.fields.notes.future,
        .parent = self.fields.parent.future,
        .mfr = self.fields.mfr.future,
    };

    var parent_search_url: []const u8 = "/pkg";
    if (self.parent_mfr.future_opt()) |parent_mfr| {
        parent_search_url = try http.tprint("/mfr:{}/pkg", .{ http.fmtForUrl(parent_mfr) });
    }

    switch (options.target) {
        .add, .edit => {
            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .mfr_id = obj.mfr,
                .title = self.fields.full_name.future_opt() orelse self.fields.id.future,
                .post_prefix = post_prefix,
                .cancel_url = "/pkg",
                .id_qualifier_field = "mfr",
                .id_qualifier = obj.mfr,
                .id_qualifier_placeholder = "Manufacturer",
                .id_qualifier_search_url = "/mfr",
                .parent_qualifier_field = "parent_mfr",
                .parent_qualifier = self.parent_mfr.future,
                .parent_qualifier_placeholder = "Manufacturer",
                .parent_qualifier_search_url = "/mfr",
                .parent_search_url = parent_search_url,
            };
            return switch (options.target) {
                .add => try req.render("pkg/add.zk", render_data, .{}),
                .edit => try req.render("pkg/edit.zk", render_data, .{}),
                else => unreachable,
            };
        },
        else => {},
    }

    { // ID row
        const is_target = switch (options.target) {
            .field => |field| field == .id or field == .mfr,
            else => false,
        };
        const is_changed = self.fields.id.is_changed() or self.fields.mfr.is_changed();
        if (is_target or is_changed) try req.render("common/post_qualified_id.zk", .{
            .validating = true,
            .saved = self.changes_applied,
            .valid = self.fields.mfr.valid and self.fields.id.valid,
            .err = if (self.fields.mfr.err.len > 0) self.fields.mfr.err else self.fields.id.err,
            .err_id = !self.fields.id.valid,
            .err_id_qualifier = !self.fields.mfr.valid,
            .swap_oob = !is_target,
            .obj = obj,
            .post_prefix = post_prefix,
            .id_qualifier_field = "mfr",
            .id_qualifier = obj.mfr,
            .id_qualifier_placeholder = "Manufacturer",
            .id_qualifier_search_url = "/mfr",
        }, .{});
    }
    { // Parent row
        const is_target = switch (options.target) {
            .field => |field| field == .parent,
            .parent_mfr => true,
            else => false,
        };
        const is_changed = self.fields.parent.is_changed() or self.parent_mfr.is_changed();
        if (is_target or is_changed) try req.render("common/post_qualified_parent.zk", .{
            .validating = true,
            .saved = self.changes_applied and self.fields.parent.future.len > 0,
            .valid = self.parent_mfr.valid and self.fields.parent.valid,
            .err = if (self.parent_mfr.err.len > 0) self.parent_mfr.err else self.fields.parent.err,
            .err_parent = !self.fields.parent.valid,
            .err_parent_qualifier = !self.parent_mfr.valid,
            .swap_oob = !is_target,
            .obj = obj,
            .post_prefix = post_prefix,
            .parent_qualifier_field = "parent_mfr",
            .parent_qualifier = self.parent_mfr.future,
            .parent_qualifier_placeholder = "Manufacturer",
            .parent_qualifier_search_url = "/mfr",
            .parent_search_url = parent_search_url,
        }, .{});
    }

    inline for (comptime std.enums.values(Field)) |field| {
        switch (field) {
            .id, .mfr, .parent => {},
            else => {
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
                    };
                    switch (field) {
                        .id, .mfr, .parent => unreachable,
                        .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
                        .notes => try req.render("common/post_notes.zk", render_data, .{}),
                    }
                }
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
}

const log = std.log.scoped(.@"http.pkg");

const additional_names_util = @import("../additional_names_util.zig");
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
