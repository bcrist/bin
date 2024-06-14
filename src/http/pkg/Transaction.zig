db: *const DB,
idx: ?Package.Index,

id: ?[]const u8 = null,
full_name: ?[]const u8 = null,
parent: ?[]const u8 = null,
mfr: ?[]const u8 = null,
notes: ?[]const u8 = null,

valid: bool = true,
err: []const u8 = "",

const Transaction = @This();

pub const Field = enum {
    id,
    full_name,
    parent,
    mfr,
    notes,
};

pub fn process_param(self: *Transaction, param: Query_Param) !void {
    if (!try self.maybe_process_param(param)) {
        log.warn("Unrecognized parameter: {s}", .{ param.name });
        return error.BadRequest;
    }
}

pub fn maybe_process_param(self: *Transaction, param: Query_Param) !bool {
    switch (std.meta.stringToEnum(Field, param.name) orelse return false) {
        inline else => |f| @field(self, @tagName(f)) = try trim(param.value),
    }
    return true;
}

fn trim(value: ?[]const u8) ![]const u8 {
    return try http.temp().dupe(u8, std.mem.trim(u8, value orelse "", &std.ascii.whitespace));
}

pub fn validate(self: *Transaction) !void {
    try self.validate_id();
    try self.validate_full_name();
    try self.validate_parent();
    try self.validate_mfr();
}

fn validate_id(self: *Transaction) !void {
    const new_id = self.id orelse return;
    self.id = new_id;

    if (!DB.is_valid_id(new_id)) {
        log.debug("Invalid ID: {s}", .{ new_id });
        self.valid = false;
        self.err = "ID may not be empty or '_', or contain '/'";
        return;
    }

    if (self.idx) |idx| {
        const current_id = Package.get_id(self.db, idx);
        if (std.mem.eql(u8, current_id, new_id)) {
            self.id = null;
            return;
        }
    }

    if (Package.maybe_lookup(self.db, new_id)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx.?) {
            log.debug("Invalid ID (in use): {s}", .{ new_id });
            self.valid = false;
            const existing_id = Package.get_id(self.db, existing_idx);
            self.err = try http.tprint("In use by <a href=\"/pkg:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
            return;
        }
    }
}

fn validate_full_name(self: *Transaction) !void {
    var new_name = self.full_name orelse return;

    if (self.id orelse if (self.idx) |idx| Package.get_id(self.db, idx) else null) |id| {
        if (std.mem.eql(u8, id, new_name)) new_name = "";
    }

    self.full_name = new_name;

    if (new_name.len == 0) {
        if (self.idx == null or Package.get_full_name(self.db, self.idx.?) == null) {
            self.full_name = null;
        }
        return;
    }

    if (Package.maybe_lookup(self.db, new_name)) |existing_idx| {
        if (self.idx) |idx| {
            if (idx == existing_idx) {
                if (Package.get_full_name(self.db, idx)) |current_full_name| {
                    if (std.mem.eql(u8, new_name, current_full_name)) {
                        self.full_name = null;
                        return;
                    }
                }
            }
        }

        log.debug("Invalid name (in use): {s}", .{ new_name });
        self.valid = false;
        const existing_id = Package.get_id(self.db, existing_idx);
        self.err = try http.tprint("In use by <a href=\"/pkg:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
    }
}

fn validate_parent(self: *Transaction) !void {
    const parent_id = self.parent orelse return;

    if (parent_id.len == 0) {
        if (self.idx == null or Package.get_parent(self.db, self.idx.?) == null) {
            self.parent = null;
        }
        return;
    }

    const parent_idx = Package.maybe_lookup(self.db, parent_id) orelse {
        log.debug("Invalid parent package: {s}", .{ parent_id });
        self.valid = false;
        self.err = "Invalid package";
        return;
    };

    self.parent = Package.get_id(self.db, parent_idx);

    if (self.idx) |idx| {
        if (Package.is_ancestor(self.db, parent_idx, idx)) {
            log.debug("Recursive package parent chain involving: {s}", .{ parent_id });
            self.valid = false;
            self.err = "Recursive packages are not allowed!";
            return;
        }

        if (Package.get_parent(self.db, idx)) |current_parent_idx| {
            if (current_parent_idx == parent_idx) {
                self.parent = null;
            }
        }
    }
}

fn validate_mfr(self: *Transaction) !void {
    const mfr_id = self.mfr orelse return;

    if (mfr_id.len == 0) {
        if (self.idx == null or Package.get_mfr(self.db, self.idx.?) == null) {
            self.mfr = null;
        }
        return;
    }

    const mfr_idx = Manufacturer.maybe_lookup(self.db, mfr_id) orelse {
        log.debug("Invalid mfr: {s}", .{ mfr_id });
        self.valid = false;
        self.err = "Invalid manufacturer";
        return;
    };

    self.mfr = Manufacturer.get_id(self.db, mfr_idx);

    if (self.idx) |idx| {
        if (Package.get_mfr(self.db, idx)) |current_mfr_idx| {
            if (current_mfr_idx == mfr_idx) {
                self.mfr = null;
            }
        }
    }
}

pub fn apply_changes(self: *Transaction, db: *DB) !void {
    if (!self.valid) return;

    const idx = idx: {
        if (self.idx) |idx| {
            break :idx idx;
        } else if (self.id) |id| {
            break :idx try Package.lookup_or_create(db, id);
        } else {
            log.warn("ID not specified", .{});
            return error.BadRequest;
        }
    };

    if (self.id) |id| {
        try Package.set_id(db, idx, id);
    }

    if (self.parent) |parent_id| {
        if (parent_id.len == 0) {
            try Package.set_parent(db, idx, null);
        } else {
            const parent_idx = Package.maybe_lookup(db, parent_id).?;
            try Package.set_parent(db, idx, parent_idx);
        }
    }

    if (self.mfr) |mfr_id| {
        if (mfr_id.len == 0) {
            try Package.set_mfr(db, idx, null);
        } else {
            const mfr_idx = Manufacturer.maybe_lookup(db, mfr_id).?;
            try Package.set_mfr(db, idx, mfr_idx);
        }
    }

    if (self.full_name) |full_name| {
        try Package.set_full_name(db, idx, if (full_name.len == 0) null else full_name);
    }

    if (self.notes) |notes| {
        try Package.set_notes(db, idx, if (notes.len == 0) null else notes);
    }
}

const log = std.log.scoped(.@"http.pkg");

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
