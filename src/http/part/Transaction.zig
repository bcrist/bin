db: *const DB,
idx: ?Part.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),
parent_mfr: Field_Data,
pkg_mfr: Field_Data,
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
            .mfr = .{},
            .id = .{},
            .parent = .{},
            .pkg = .{},
            .notes = .{},
        },
        .parent_mfr = .{},
        .pkg_mfr = .{},
        .dist_pns = .{},
    };
}

pub fn init_idx(db: *const DB, idx: Part.Index) !Transaction {
    const part = Part.get(db, idx);

    const parent_mfr: Field_Data = if (part.parent) |parent_idx|
        try Field_Data.init(db, Part.get_mfr(db, parent_idx)) else .{};

    const pkg_mfr: Field_Data = if (part.pkg) |pkg_idx|
        try Field_Data.init(db, Package.get_mfr(db, pkg_idx)) else .{};

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
        .pkg_mfr = pkg_mfr,
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

    if (std.mem.eql(u8, param.name, "pkg_mfr")) {
        const value = try trim(param.value);
        self.pkg_mfr.set_processed(value, self.idx == null);
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
    try self.validate_mfr(&self.fields.mfr);
    try self.validate_id();
    try self.validate_mfr(&self.parent_mfr);
    try self.validate_parent();
    try self.validate_mfr(&self.pkg_mfr);
    try self.validate_pkg();

    const dist_pns = self.dist_pns.values();
    for (0.., self.dist_pns.keys(), dist_pns) |i, dist_pn_index, *dist_pn| {
        try self.validate_dist_pn(dist_pn_index, dist_pn, dist_pns[0..i]);
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
            const maybe_existing_mfr_idx = Part.get_mfr(self.db, existing_idx);
            if (maybe_existing_mfr_idx) |existing_mfr_idx| {
                self.fields.id.err = try http.tprint("In use by <a href=\"/mfr:{}/p:{}\" target=\"_blank\">{s}</a>", .{
                    http.fmtForUrl(Manufacturer.get_id(self.db, existing_mfr_idx)),
                    http.fmtForUrl(existing_id),
                    existing_id,
                });
            } else {
                self.fields.id.err = try http.tprint("In use by <a href=\"/p:{}\" target=\"_blank\">{s}</a>", .{
                    http.fmtForUrl(existing_id),
                    existing_id,
                });
            }
            self.fields.id.valid = false;
            self.valid = false;
            return;
        }
    }
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

    const mfr_idx = Manufacturer.maybe_lookup(self.db, self.pkg_mfr.future);

    const pkg_idx = Package.maybe_lookup(self.db, mfr_idx, self.fields.pkg.future) orelse {
        log.debug("Invalid package: {s}", .{ self.fields.pkg.future });
        self.fields.pkg.err = "Invalid package";
        self.fields.pkg.valid = false;
        self.valid = false;
        return;
    };

    self.fields.pkg.future = Package.get_id(self.db, pkg_idx);
}

fn validate_dist_pn(self: *Transaction, index_str: []const u8, dist_pn: *Distributor_Part_Number_Data, prev_dist_pns: []const Distributor_Part_Number_Data) !void {
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

    if (Distributor.maybe_lookup(self.db, dist_pn.dist.future)) |dist_idx| {
        dist_pn.dist.future = Distributor.get_id(self.db, dist_idx);
        if (Part.lookup_dist_pn(self.db, dist_idx, dist_pn.pn.future)) |existing_part_idx| {
            if (self.idx != existing_part_idx) {
                log.debug("Invalid distributor part number (in use): {s} {s}", .{ dist_pn.dist.future, dist_pn.pn.future });
                const existing_part_id = Part.get_id(self.db, existing_part_idx);
                const maybe_existing_mfr_idx = Part.get_mfr(self.db, existing_part_idx);
                if (maybe_existing_mfr_idx) |existing_mfr_idx| {
                    dist_pn.pn.err = try http.tprint("In use by <a href=\"/mfr:{}/p:{}\" target=\"_blank\">{s}</a>", .{
                        http.fmtForUrl(Manufacturer.get_id(self.db, existing_mfr_idx)),
                        http.fmtForUrl(existing_part_id),
                        existing_part_id,
                    });
                } else {
                    dist_pn.pn.err = try http.tprint("In use by <a href=\"/p:{}\" target=\"_blank\">{s}</a>", .{
                        http.fmtForUrl(existing_part_id),
                        existing_part_id,
                    });
                }
                dist_pn.err = dist_pn.pn.err;
                dist_pn.pn.valid = false;
                dist_pn.valid = false;
                self.valid = false;
                return;
            }
        }
    } else {
        log.debug("Distributor not found: {s}", .{ dist_pn.dist.future });
        dist_pn.dist.err = "Distributor not found";
        dist_pn.err = dist_pn.dist.err;
        dist_pn.dist.valid = false;
        dist_pn.valid = false;
        self.valid = false;
        return;
    }

    for (prev_dist_pns) |prev_pn| {
        if (!prev_pn.valid) continue;
        if (!std.mem.eql(u8, dist_pn.dist.future, prev_pn.dist.future)) continue;
        if (!std.ascii.eqlIgnoreCase(dist_pn.pn.future, prev_pn.pn.future)) continue;

        dist_pn.dist.future.len = 0;
        dist_pn.pn.future.len = 0;
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
            const pkg_mfr_idx = Manufacturer.maybe_lookup(db, self.pkg_mfr.future_opt());
            const pkg_idx = Package.maybe_lookup(db, pkg_mfr_idx, pkg).?;
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

        log.debug("changes applied: created", .{});
        self.changes_applied = true;
        self.created_idx = idx;
        return;
    };

    if (self.fields.id.is_changed() or self.fields.mfr.is_changed()) {
        const mfr_idx = Manufacturer.maybe_lookup(db, self.fields.mfr.future_opt());
        try Part.set_id(db, idx, mfr_idx, self.fields.id.future);
        log.debug("changes applied: ID/mfr changed", .{});
        self.changes_applied = true;
    }

    if (self.fields.notes.changed()) |notes| {
        try Part.set_notes(db, idx, notes.future_opt());
        log.debug("changes applied: notes changed", .{});
        self.changes_applied = true;
    }

    if (self.fields.parent.is_removed()) {
        try Part.set_parent(db, idx, null);
        log.debug("changes applied: parent removed", .{});
        self.changes_applied = true;
    } else if (self.fields.parent.future_opt()) |parent_id| {
        if (self.fields.parent.is_changed() or self.parent_mfr.is_changed()) {
            const parent_mfr_idx = Manufacturer.maybe_lookup(db, self.parent_mfr.future_opt());
            const parent_idx = Part.maybe_lookup(db, parent_mfr_idx, parent_id).?;
            try Part.set_parent(db, idx, parent_idx);
            log.debug("changes applied: parent changed", .{});
            self.changes_applied = true;
        }
    }

    if (self.fields.pkg.is_removed()) {
        try Part.set_pkg(db, idx, null);
        log.debug("changes applied: pkg removed", .{});
        self.changes_applied = true;
    } else if (self.fields.pkg.future_opt()) |pkg_id| {
        if (self.fields.pkg.is_changed() or self.pkg_mfr.is_changed()) {
            const pkg_mfr_idx = Manufacturer.maybe_lookup(db, self.pkg_mfr.future_opt());
            const pkg_idx = Package.maybe_lookup(db, pkg_mfr_idx, pkg_id).?;
            try Part.set_pkg(db, idx, pkg_idx);
            log.debug("changes applied: pkg changed", .{});
            self.changes_applied = true;
        }
    }

    for (self.dist_pns.values()) |dist_pn| {
        if (dist_pn.dist.is_removed() or dist_pn.pn.is_removed()) {
            try Part.remove_dist_pn(db, idx, .{
                .dist = Distributor.maybe_lookup(db, dist_pn.dist.current).?,
                .pn = dist_pn.pn.current,
            });
            log.debug("changes applied: dist PN removed", .{});
            self.changes_applied = true;
        } else if (dist_pn.dist.future.len > 0 and dist_pn.pn.future.len > 0) {
            if (dist_pn.dist.is_added() or dist_pn.pn.is_added()) {
                try Part.add_dist_pn(db, idx, .{
                    .dist = Distributor.maybe_lookup(db, dist_pn.dist.future).?,
                    .pn = dist_pn.pn.future,
                });
                log.debug("changes applied: dist PN added", .{});
                self.changes_applied = true;
            } else if (dist_pn.dist.is_edited() or dist_pn.pn.is_edited()) {
                try Part.edit_dist_pn(db, idx, .{
                    .dist = Distributor.maybe_lookup(db, dist_pn.dist.current).?,
                    .pn = dist_pn.pn.current,
                }, .{
                    .dist = Distributor.maybe_lookup(db, dist_pn.dist.future).?,
                    .pn = dist_pn.pn.future,
                });
                log.debug("changes applied: dist PN edited", .{});
                self.changes_applied = true;
            }
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
        pkg_mfr,
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

    const obj = Field_Data.future_obj(Field, self.fields);

    var parent_search_url: []const u8 = "/p";
    if (self.parent_mfr.future_opt()) |parent_mfr| {
        parent_search_url = try http.tprint("/mfr:{}/p", .{ http.fmtForUrl(parent_mfr) });
    }

    switch (options.target) {
        .add, .edit => {
            const dist_pns = try http.temp().alloc(common.Distributor_Part_Number, self.dist_pns.count());
            for (dist_pns, self.dist_pns.values()) |*out, pn| {
                out.* = .{
                    .dist = pn.dist.future,
                    .pn = pn.pn.future,
                };
            }

            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .mfr_id = obj.mfr,
                .pkg_mfr = self.pkg_mfr.future,
                .title = self.fields.id.future,
                .dist_pns = dist_pns,
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
    { // Package row
        const is_target = switch (options.target) {
            .field => |field| field == .pkg,
            .pkg_mfr => true,
            else => false,
        };
        const is_changed = self.fields.pkg.is_changed() or self.pkg_mfr.is_changed();
        if (is_target or is_changed) try req.render("part/post_pkg.zk", .{
            .validating = true,
            .saved = self.changes_applied and self.fields.pkg.future.len > 0,
            .valid = self.pkg_mfr.valid and self.fields.pkg.valid,
            .err = if (self.pkg_mfr.err.len > 0) self.pkg_mfr.err else self.fields.pkg.err,
            .err_pkg = !self.fields.pkg.valid,
            .err_mkg_mfr = !self.pkg_mfr.valid,
            .swap_oob = !is_target,
            .obj = obj,
            .post_prefix = post_prefix,
            .pkg_mfr = self.pkg_mfr.future,
        }, .{});
    }

    inline for (comptime std.enums.values(Field)) |field| {
        switch (field) {
            .id, .mfr, .parent, .pkg => {},
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
                        .id, .mfr, .parent, .pkg => unreachable,
                        .notes => try req.render("common/post_notes.zk", render_data, .{}),
                    }
                }
            }
        }
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
            .swap_oob = if (is_target) null else try http.tprint("outerHTML:#part_dist_pn{s}", .{ index_str }),

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
const common = @import("../part.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const std = @import("std");
