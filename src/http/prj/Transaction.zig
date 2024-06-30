db: *const DB,
idx: ?Project.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),

add_another: bool = false,
was_valid: bool = true,
valid: bool = true,
changes_applied: bool = false,
names_changed: bool = false,
created_idx: ?Project.Index = null,

pub const Field = enum {
    id,
    full_name,
    parent,
    status,
    notes,
};

const Transaction = @This();

pub fn init_empty(db: *const DB) Transaction {
    return .{
        .db = db,
        .idx = null,
        .fields = .{
            .id = .{},
            .full_name = .{},
            .parent = .{},
            .notes = .{},
            .status = .{
                .current = "active",
                .future = "active",
            },
        },
    };
}

pub fn init_idx(db: *const DB, idx: Project.Index) !Transaction {
    const prj = Project.get(db, idx);
    return .{
        .db = db,
        .idx = idx,
        .fields = try Field_Data.init_fields(Field, db, prj),
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
    try self.validate_name(&self.fields.id, .id);
    try self.validate_name(&self.fields.full_name, .full_name);
    try self.validate_parent();
    try self.validate_status();
}

fn validate_name(self: *Transaction, data: *Field_Data, field: Field) !void {
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

    if (Project.maybe_lookup(self.db, data.future)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx) {
            log.debug("Invalid ID (in use): {s}", .{ data.future });
            const existing_id = Project.get_id(self.db, existing_idx);
            data.err = try http.tprint("In use by <a href=\"/prj:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
            data.valid = false;
            self.valid = false;
            return;
        }
    }
}

fn validate_status(self: *Transaction) !void {
    if (null == std.meta.stringToEnum(Project.Status, self.fields.status.future)) {
        log.debug("Invalid project status: {s}", .{ self.fields.status.future });
        self.fields.status.err = "Invalid status";
        self.fields.status.valid = false;
        self.valid = false;
    }
}

fn validate_parent(self: *Transaction) !void {
    if (self.fields.parent.future.len == 0) return;

    const parent_idx = Project.maybe_lookup(self.db, self.fields.parent.future) orelse {
        log.debug("Invalid parent project: {s}", .{ self.fields.parent.future });
        self.fields.parent.err = "Invalid project";
        self.fields.parent.valid = false;
        self.valid = false;
        return;
    };

    self.fields.parent.future = Project.get_id(self.db, parent_idx);

    if (self.idx) |idx| {
        if (Project.is_ancestor(self.db, parent_idx, idx)) {
            log.debug("Recursive project parent chain involving: {s}", .{ self.fields.parent.future });
            self.fields.parent.err = "Recursive projects are not allowed!";
            self.fields.parent.valid = false;
            self.valid = false;
            return;
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

        const idx = try Project.lookup_or_create(db, id_str);
        try Project.set_full_name(db, idx, self.fields.full_name.future_opt());
        try Project.set_status(db, idx, self.fields.status.future_enum(Project.Status));
        try Project.set_notes(db, idx, self.fields.notes.future_opt());

        if (self.fields.parent.future_opt()) |parent| {
            const parent_idx = Project.maybe_lookup(db, parent).?;
            try Project.set_parent(db, idx, parent_idx);
        }

        self.changes_applied = true;
        self.created_idx = idx;
        return;
    };

    if (self.names_changed) {
        try Project.set_full_name(db, idx, null);
        try Project.set_id(db, idx, self.fields.id.future);
        try Project.set_full_name(db, idx, self.fields.full_name.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.status.changed()) |status| {
        try Project.set_status(db, idx, status.future_enum(Project.Status));
        self.changes_applied = true;
    }
    
    if (self.fields.notes.changed()) |notes| {
        try Project.set_notes(db, idx, notes.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.parent.is_removed()) {
        try Project.set_parent(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.parent.changed()) |parent| {
        const parent_idx = Project.maybe_lookup(db, parent.future).?;
        try Project.set_parent(db, idx, parent_idx);
        self.changes_applied = true;
    }
}

pub fn get_post_prefix(db: *const DB, maybe_idx: ?Project.Index) ![]const u8 {
    if (maybe_idx) |idx| {
        const id = Project.get_id(db, idx);
        return try http.tprint("/prj:{}", .{ http.fmtForUrl(id) });
    }
    return "/prj";
}

const Render_Options = struct {
    target: union (enum) {
        add,
        edit,
        field: Field,
    },
    rnd: ?*std.rand.Xoshiro256,
};

pub fn render_results(self: Transaction, session: ?Session, req: *http.Request, options: Render_Options) !void {
    const post_prefix = try get_post_prefix(self.db, self.created_idx orelse self.idx);

    if (self.changes_applied) {
        if (self.created_idx != null) {
            if (self.add_another) {
                try req.redirect(try http.tprint("/prj/add{s}", .{ req.hx_current_query() }), .see_other);
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

    const obj: std.enums.EnumFieldStruct(Field, []const u8, null) = .{
        .id = self.fields.id.future,
        .full_name = self.fields.full_name.future,
        .status = self.fields.status.future,
        .notes = self.fields.notes.future,
        .parent = self.fields.parent.future,
    };

    switch (options.target) {
        .add, .edit => {
            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .title = self.fields.full_name.future_opt() orelse self.fields.id.future,
                .post_prefix = post_prefix,
                .parent_search_url = "/prj",
                .cancel_url = "/prj",
            };
            return switch (options.target) {
                .add => try req.render("prj/add.zk", render_data, .{}),
                .edit => try req.render("prj/edit.zk", render_data, .{}),
                else => unreachable,
            };
        },
        .field => |target_field| inline for (comptime std.enums.values(Field)) |field| {
            const is_target = field == target_field;
            const data = @field(self.fields, @tagName(field));
            if (is_target or data.is_changed()) {
                var status_str: []const u8 = "";
                if (field == .status) {
                    if (std.meta.stringToEnum(Project.Status, data.future)) |status| {
                        status_str = status.display();
                    }
                }
                const render_data = .{
                    .validating = true,
                    .saved = self.changes_applied,
                    .valid = data.valid,
                    .err = data.err,
                    .swap_oob = !is_target,
                    .obj = obj,
                    .status_str = status_str,
                    .post_prefix = post_prefix,
                    .parent_search_url = "/prj",
                };
                switch (field) {
                    .id => try req.render("common/post_id.zk", render_data, .{}),
                    .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
                    .status => try req.render("prj/post_status.zk", render_data, .{}),
                    .notes => try req.render("common/post_notes.zk", render_data, .{}),
                    .parent => try req.render("common/post_parent.zk", render_data, .{}),
                }
            }
        },
    }
}

const log = std.log.scoped(.@"http.prj");

const Project = DB.Project;
const DB = @import("../../DB.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
