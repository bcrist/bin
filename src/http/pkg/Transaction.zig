db: *const DB,
idx: ?Package.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),

was_valid: bool = true,
valid: bool = true,
changes_applied: bool = false,
names_changed: bool = false,

pub const Field = enum {
    id,
    full_name,
    parent,
    mfr,
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
            .mfr = .{},
            .notes = .{},
        },
    };
}

pub fn init_idx(db: *const DB, idx: Package.Index) !Transaction {
    const pkg = Package.get(db, idx);
    return .{
        .db = db,
        .idx = idx,
        .fields = try Field_Data.init_fields(Field, db, pkg),
    };
}

pub fn process_all_params(self: *Transaction, req: *http.Request) !void {
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
    try self.validate_mfr();
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

    if (Package.maybe_lookup(self.db, data.future)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx.?) {
            log.debug("Invalid ID (in use): {s}", .{ data.future });
            const existing_id = Package.get_id(self.db, existing_idx);
            data.err = try http.tprint("In use by <a href=\"/pkg:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
            data.valid = false;
            self.valid = false;
            return;
        }
    }
}

fn validate_parent(self: *Transaction) !void {
    if (self.fields.parent.future.len == 0) return;

    const parent_idx = Package.maybe_lookup(self.db, self.fields.parent.future) orelse {
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

fn validate_mfr(self: *Transaction) !void {
    if (self.fields.mfr.future.len == 0) return;

    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.fields.mfr.future) orelse {
        log.debug("Invalid manufacturer: {s}", .{ self.fields.mfr.future });
        self.fields.mfr.err = "Invalid manufacturer";
        self.fields.mfr.valid = false;
        self.valid = false;
        return;
    };

    self.fields.mfr.future = Manufacturer.get_id(self.db, mfr_idx);
}

pub fn apply_changes(self: *Transaction, db: *DB) !void {
    if (!self.valid) return;

    const idx = self.idx orelse {
        const id_str = self.fields.id.future_opt() orelse {
            log.warn("ID not specified", .{});
            return error.BadRequest;
        };

        const idx = try Package.lookup_or_create(db, id_str);
        try Package.set_full_name(db, idx, self.fields.full_name.future_opt());
        try Package.set_notes(db, idx, self.fields.notes.future_opt());
        
        if (self.fields.parent.future_opt()) |parent| {
            const parent_idx = Package.maybe_lookup(db, parent).?;
            try Package.set_parent(db, idx, parent_idx);
        }

        if (self.fields.mfr.future_opt()) |mfr| {
            const mfr_idx = Manufacturer.maybe_lookup(db, mfr).?;
            try Package.set_mfr(db, idx, mfr_idx);
        }

        self.changes_applied = true;
        return;
    };

    if (self.names_changed) {
        try Package.set_full_name(db, idx, null);
        try Package.set_id(db, idx, self.fields.id.future);
        try Package.set_full_name(db, idx, self.fields.full_name.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.notes.changed()) |notes| {
        try Package.set_notes(db, idx, notes.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.parent.is_removed()) {
        try Package.set_parent(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.parent.changed()) |parent| {
        const parent_idx = Package.maybe_lookup(db, parent.future).?;
        try Package.set_parent(db, idx, parent_idx);
        self.changes_applied = true;
    }

    if (self.fields.mfr.is_removed()) {
        try Package.set_mfr(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.mfr.changed()) |mfr| {
        const mfr_idx = Manufacturer.maybe_lookup(db, mfr.future).?;
        try Package.set_mfr(db, idx, mfr_idx);
        self.changes_applied = true;
    }
}

const Render_Options = struct {
    target: union (enum) {
        add,
        edit,
        field: Field,
    },
    post_prefix: []const u8,
    rnd: ?*std.rand.Xoshiro256,
};

pub fn render_results(self: Transaction, session: ?Session, req: *http.Request, options: Render_Options) !void {
    if (self.changes_applied) if (self.fields.id.edited()) |id| {
        try req.see_other(try http.tprint("/pkg:{}?edit", .{ http.fmtForUrl(id.future) }));
        return;
    };

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

    switch (options.target) {
        .add, .edit => {
            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .title = self.fields.full_name.future_opt() orelse self.fields.id.future,
                .post_prefix = options.post_prefix,
                .parent_search_url = "/pkg",
                .cancel_url = "/pkg",
            };
            return switch (options.target) {
                .add => try req.render("pkg/add.zk", render_data, .{}),
                .edit => try req.render("pkg/edit.zk", render_data, .{}),
                else => unreachable,
            };
        },
        .field => |target_field| inline for (comptime std.enums.values(Field)) |field| {
            const is_target = field == target_field;
            const data = @field(self.fields, @tagName(field));
            if (is_target or data.is_changed()) {
                const render_data = .{
                    .validating = true,
                    .saved = self.changes_applied,
                    .valid = data.valid,
                    .err = data.err,
                    .swap_oob = !is_target,
                    .obj = obj,
                    .post_prefix = options.post_prefix,
                    .parent_search_url = "/pkg",
                };
                switch (field) {
                    .id => try req.render("common/post_id.zk", render_data, .{}),
                    .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
                    .notes => try req.render("common/post_notes.zk", render_data, .{}),
                    .parent => try req.render("common/post_parent.zk", render_data, .{}),
                    .mfr => try req.render("common/post_mfr.zk", render_data, .{}),
                }
            }
        },
    }
}

const log = std.log.scoped(.@"http.pkg");

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
