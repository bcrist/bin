db: *const DB,
idx: ?Part.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),
parent_mfr: Field_Data,
dist_pns: std.StringArrayHashMapUnmanaged(Distributor_Part_Number_Data),

add_another: bool = false,
was_valid: bool = true,
valid: bool = true,
changes_applied: bool = false,
created_idx: ?Part.Index = null,

pub const Field = enum {
    mfr,
    id,
    parent,
    pkg,
    notes,
};

pub const Distributor_Part_Number_Data = struct {
    dist: Field_Data = .{},
    pn: Field_Data = .{},
    valid: bool = true,
    err: []const u8 = "",

    pub fn fields_processed(self: Distributor_Part_Number_Data) u2 {
        var result: u2 = 0;
        if (self.dist.processed) result += 1;
        if (self.pn.processed) result += 1;
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
            .parent = .{},
            .mfr = .{},
            .pkg = .{},
            .notes = .{},
        },
        .parent_mfr = .{},
        .dist_pns = .{},
    };
}

pub fn init_idx(db: *const DB, idx: Part.Index) !Transaction {
    const part = Part.get(db, idx);

    const parent_mfr: Field_Data = if (part.parent) |parent_idx| try Field_Data.init(db, parent_idx) else .{};

    var dist_pns: std.StringArrayHashMapUnmanaged(Distributor_Part_Number_Data) = .{};
    try dist_pns.ensureTotalCapacity(http.temp(), part.dist_pns.items.len);

    for (0.., part.dist_pns.items) |i, pn| {
        const key = try http.tprint("{d}", .{ i });
        dist_pns.putAssumeCapacity(key, .{
            .dist = try Field_Data.init(db, pn.dist),
            .pn = try Field_Data.init(db, pn.pn),
        });
    }

    return .{
        .db = db,
        .idx = idx,
        .fields = try Field_Data.init_fields(Field, db, part),
        .parent_mfr = parent_mfr,
        .dist_pns = dist_pns,
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
    
    if (std.mem.startsWith(u8, param.name, "dist_pn_order")) {
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "dist")) {
        const index_str = param.name["dist".len..];
        const value = try trim(param.value);

        const gop = try self.dist_pns.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.dist.set_processed(value, self.idx == null);
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "pn")) {
        const index_str = param.name["pn".len..];
        const value = try trim(param.value);

        const gop = try self.dist_pns.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.pn.set_processed(value, self.idx == null);
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
    try self.validate_mfr();
    try self.validate_id();
    try self.validate_parent_mfr();
    try self.validate_parent();
    try self.validate_pkg();

    for (self.dist_pns.keys(), self.dist_pns.values()) |dist_pn_index, *dist_pn| {
        try self.validate_dist_pn(dist_pn_index, dist_pn);
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

fn validate_id(self: *Transaction) !void {
    if (!DB.is_valid_id(self.fields.id.future)) {
        log.debug("Invalid ID: {s}", .{ self.fields.id.future });
        self.fields.id.err = "ID may not be empty or '_', or contain '/'";
        self.fields.id.valid = false;
        self.valid = false;
        return;
    }

    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.fields.mfr.future);

    if (Part.maybe_lookup(self.db, mfr_idx, self.fields.id.future)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx.?) {
            log.debug("Invalid ID (in use): {s}", .{ self.fields.id.future });
            const existing_id = Part.get_id(self.db, existing_idx);
            self.fields.id.err = try http.tprint("In use by <a href=\"/p:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
            self.fields.id.valid = false;
            self.valid = false;
            return;
        }
    }
}

fn validate_parent_mfr(self: *Transaction) !void {
    if (self.parent_mfr.future.len == 0) return;

    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.parent_mfr.future) orelse {
        log.debug("Invalid parent manufacturer: {s}", .{ self.parent_mfr.future });
        self.parent_mfr.err = "Invalid manufacturer";
        self.parent_mfr.valid = false;
        self.valid = false;
        return;
    };

    self.parent_mfr.future = Manufacturer.get_id(self.db, mfr_idx);
}

fn validate_parent(self: *Transaction) !void {
    if (self.fields.parent.future.len == 0) return;

    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.parent_mfr.future);

    const parent_idx = Part.maybe_lookup(self.db, mfr_idx, self.fields.parent.future) orelse {
        log.debug("Invalid parent part: {s}", .{ self.fields.parent.future });
        self.fields.parent.err = "Invalid part";
        self.fields.parent.valid = false;
        self.valid = false;
        return;
    };

    self.fields.parent.future = Part.get_id(self.db, parent_idx);

    if (self.idx) |idx| {
        if (Part.is_ancestor(self.db, parent_idx, idx)) {
            log.debug("Recursive part parent chain involving: {s}", .{ self.fields.parent.future });
            self.fields.parent.err = "Recursive parts are not allowed!";
            self.fields.parent.valid = false;
            self.valid = false;
            return;
        }
    }
}

fn validate_pkg(self: *Transaction) !void {
    if (self.fields.pkg.future.len == 0) return;

    const pkg_idx = Package.maybe_lookup(self.db, self.fields.pkg.future) orelse {
        log.debug("Invalid package: {s}", .{ self.fields.pkg.future });
        self.fields.pkg.err = "Invalid package";
        self.fields.pkg.valid = false;
        self.valid = false;
        return;
    };

    self.fields.pkg.future = Package.get_id(self.db, pkg_idx);
}

fn validate_dist_pn(self: *Transaction, index_str: []const u8, dist_pn: *Distributor_Part_Number_Data) !void {
    const fields_processed = dist_pn.fields_processed();
    if (fields_processed == 0) return;
    if (fields_processed != 2) {
        log.warn("Expected parameters dist{s} and pn{s}", .{
            index_str, index_str,
        });
        return error.BadRequest;
    }

    if (dist_pn.dist.future.len == 0) return;
    if (dist_pn.pn.future.len == 0) return;

    if (Distributor.maybe_lookup(self.db, dist_pn.dist.future)) |other_idx| {
        dist_pn.dist.future = Distributor.get_id(self.db, other_idx);
    } else {
        log.debug("Distributor not found: {s}", .{ dist_pn.dist.future });
        dist_pn.dist.err = "Distributor not found";
        dist_pn.dist.valid = false;
        dist_pn.err = dist_pn.dist.err;
        dist_pn.valid = false;
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

        const mfr_idx = Manufacturer.maybe_lookup(db, self.fields.mfr.future_opt());

        const idx = try Part.lookup_or_create(db, mfr_idx, id_str);
        try Part.set_notes(db, idx, self.fields.notes.future_opt());
        
        if (self.fields.parent.future_opt()) |parent| {
            const parent_mfr_idx = Manufacturer.maybe_lookup(db, self.parent_mfr.future_opt());
            const parent_idx = Part.maybe_lookup(db, parent_mfr_idx, parent).?;
            try Part.set_parent(db, idx, parent_idx);
        }

        if (self.fields.pkg.future_opt()) |pkg| {
            const pkg_idx = Package.maybe_lookup(db, pkg).?;
            try Part.set_pkg(db, idx, pkg_idx);
        }

        for (self.dist_pns.values()) |dist_pn| {
            if (dist_pn.dist.future_opt()) |dist| {
                if (dist_pn.pn.future_opt()) |pn| {
                    try Part.add_dist_pn(db, idx, .{
                        .dist = Distributor.maybe_lookup(db, dist).?,
                        .pn = pn,
                    });
                }
            }
        }

        self.changes_applied = true;
        self.created_idx = idx;
        return;
    };

    if (self.fields.id.is_changed() or self.fields.mfr.is_changed()) {
        const mfr_idx = Manufacturer.maybe_lookup(db, self.fields.mfr.future_opt());
        try Part.set_id(db, idx, mfr_idx, self.fields.id.future);
        self.changes_applied = true;
    }

    if (self.fields.notes.changed()) |notes| {
        try Part.set_notes(db, idx, notes.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.parent.is_removed()) {
        try Part.set_parent(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.parent.is_changed() or self.parent_mfr.is_changed()) {
        const parent_mfr_idx = Manufacturer.maybe_lookup(db, self.parent_mfr.future_opt());
        const parent_idx = Part.maybe_lookup(db, parent_mfr_idx, self.fields.parent.future).?;
        try Part.set_parent(db, idx, parent_idx);
        self.changes_applied = true;
    }

    if (self.fields.pkg.is_removed()) {
        try Part.set_pkg(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.pkg.changed()) |pkg| {
        const pkg_idx = Package.maybe_lookup(db, pkg.future).?;
        try Part.set_pkg(db, idx, pkg_idx);
        self.changes_applied = true;
    }

    for (self.dist_pns.values()) |dist_pn| {
        if (dist_pn.dist.is_removed() or dist_pn.pn.is_removed()) {
            try Part.remove_dist_pn(db, idx, .{
                .dist = Distributor.maybe_lookup(db, dist_pn.dist.current).?,
                .pn = dist_pn.pn.current,
            });
            self.changes_applied = true;
        } else if (dist_pn.dist.future.len > 0 and dist_pn.pn.future.len > 0) {
            if (dist_pn.dist.current.len > 0) {
                try Part.edit_dist_pn(db, idx, .{
                    .dist = Distributor.maybe_lookup(db, dist_pn.dist.current).?,
                    .pn = dist_pn.pn.current,
                }, .{
                    .dist = Distributor.maybe_lookup(db, dist_pn.dist.future).?,
                    .pn = dist_pn.pn.future,
                });
            } else {
                try Part.add_dist_pn(db, idx, .{
                    .dist = Distributor.maybe_lookup(db, dist_pn.dist.future).?,
                    .pn = dist_pn.pn.future,
                });
            }
            self.changes_applied = true;
        }
    }
}

pub fn get_post_prefix(db: *const DB, maybe_idx: ?Part.Index) ![]const u8 {
    if (maybe_idx) |idx| {
        const id = Part.get_id(db, idx);
        if (Part.get_mfr(db, idx)) |mfr_idx| {
            const mfr_id = Manufacturer.get_id(db, mfr_idx);
            return try http.tprint("/mfr:{}/p:{}", .{ http.fmtForUrl(mfr_id), http.fmtForUrl(id) });
        } else {
            return try http.tprint("/p:{}", .{ http.fmtForUrl(id) });
        }
    }
    return "/p";
}

const Render_Options = struct {
    target: union (enum) {
        add,
        edit,
        field: Field,
        parent_mfr,
        dist_pn: []const u8,
    },
    rnd: ?*std.rand.Xoshiro256,
};

pub fn render_results(self: Transaction, session: ?Session, req: *http.Request, options: Render_Options) !void {
    const post_prefix = try get_post_prefix(self.db, self.created_idx orelse self.idx);

    if (self.changes_applied) {
        if (self.created_idx != null) {
            if (self.add_another) {
                try req.redirect(try http.tprint("/p/add{s}", .{ req.hx_current_query() }), .see_other);
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
        .notes = self.fields.notes.future,
        .parent = self.fields.parent.future,
        .mfr = self.fields.mfr.future,
        .pkg = self.fields.pkg.future,
    };

    var parent_search_url: []const u8 = "/p";
    if (self.parent_mfr.future_opt()) |parent_mfr| {
        parent_search_url = try http.tprint("/mfr:{}/p", .{ http.fmtForUrl(parent_mfr) });
    }

    switch (options.target) {
        .add, .edit => {
            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .title = self.fields.id.future,
                .post_prefix = post_prefix,
                .cancel_url = "/p",
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
                .add => try req.render("part/add.zk", render_data, .{}),
                .edit => try req.render("part/edit.zk", render_data, .{}),
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
                .err = if (data.err.len > 0) data.err else switch (field) {
                    .id => self.fields.mfr.err,
                    .mfr => self.fields.id.err,
                    .parent => self.parent_mfr.err,
                    else => null,
                },
                .err_id = !self.fields.id.valid,
                .err_id_qualifier = !self.fields.mfr.valid,
                .err_parent = !self.fields.parent.valid,
                .err_parent_qualifier = !self.parent_mfr.valid,
                .swap_oob = !is_target,
                .obj = obj,
                .post_prefix = post_prefix,
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
            switch (field) {
                .mfr, .id => try req.render("common/post_qualified_id.zk", render_data, .{}),
                .parent => try req.render("common/post_qualified_parent.zk", render_data, .{}),
                .notes => try req.render("common/post_notes.zk", render_data, .{}),
                .pkg => try req.render("part/post_pkg.zk", render_data, .{}),
            }
        }
    }

    if (options.target == .parent_mfr or self.parent_mfr.is_changed()) {
        const render_data = .{
            .validating = true,
            .saved = self.changes_applied,
            .valid = self.parent_mfr.valid,
            .err = if (self.parent_mfr.err.len > 0) self.parent_mfr.err else self.fields.parent.err,
            .err_parent = !self.fields.parent.valid,
            .err_parent_qualifier = !self.parent_mfr.valid,
            .swap_oob = options.target != .parent_mfr,
            .obj = obj,
            .post_prefix = post_prefix,
            .parent_qualifier_field = "parent_mfr",
            .parent_qualifier = self.parent_mfr.future,
            .parent_qualifier_placeholder = "Manufacturer",
            .parent_qualifier_search_url = "/mfr",
            .parent_search_url = parent_search_url,
        };
        try req.render("common/post_qualified_parent.zk", render_data, .{});
    }

    var dist_pn_index: usize = 0;
    for (self.dist_pns.keys(), self.dist_pns.values()) |index_str, data| {
        const is_target = switch (options.target) {
            .dist_pn => |target_index| std.mem.eql(u8, index_str, target_index),
            else => false,
        };
        const is_changed = data.dist.is_changed() or data.pn.is_changed();

        const is_index_changed = if (self.idx != null and index_str.len > 0) is_index_changed: {
            const old_dist_pn_index = try std.fmt.parseInt(u16, index_str, 10);
            break :is_index_changed dist_pn_index != old_dist_pn_index;
        } else false;
        
        if (!is_target and !is_changed and !is_index_changed) {
            dist_pn_index += 1;
            continue;
        }
        
        var new_index_buf: [32]u8 = undefined;
        var new_index: []const u8 = if (is_index_changed) try http.tprint("{d}", .{ dist_pn_index }) else index_str;
        var is_placeholder = true;

        if (index_str.len > 0) {
            if (data.dist.future.len == 0 or data.pn.future.len == 0) {
                if (is_target) {
                    _ = try req.response();
                } else {
                    try req.render("part/post_dist_pn.zk", .{
                        .index = index_str,
                        .swap_oob = "delete",
                    }, .{});
                }
                continue;
            }
            dist_pn_index += 1;
            is_placeholder = false;
        } else if (data.dist.future.len > 0 and data.pn.future.len > 0 and data.valid) {
            if (options.rnd) |rnd| {
                var buf: [16]u8 = undefined;
                rnd.fill(&buf);
                const Base64 = std.base64.url_safe_no_pad.Encoder;
                new_index = Base64.encode(&new_index_buf, &buf);
            } else {
                new_index = try std.fmt.bufPrint(&new_index_buf, "{d}", .{ self.dist_pns.count() - 1 });
            }
            is_placeholder = false;
        }

        const render_data = .{
            .saved = self.changes_applied and is_changed,
            .valid = data.valid,
            .err = data.err,
            .post_prefix = post_prefix,
            .index = if (is_placeholder) null else new_index,
            .swap_oob = if (is_target) null else try http.tprint("outerHTML:#dist_pn{s}", .{ index_str }),

            .dist = data.dist.future,
            .err_dist = !data.dist.valid,

            .pn = data.pn.future,
            .err_pn = !data.pn.valid,
        };

        if (is_placeholder) {
            try req.render("part/post_dist_pn_placeholder.zk", render_data, .{});
        } else {
            try req.render("part/post_dist_pn.zk", render_data, .{});
            if (index_str.len == 0) {
                try req.render("part/post_dist_pn_placeholder.zk", .{
                    .post_prefix = post_prefix,
                }, .{});
            }
        }
    }
}

const log = std.log.scoped(.@"http.part");

const Part = DB.Part;
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const DB = @import("../../DB.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
