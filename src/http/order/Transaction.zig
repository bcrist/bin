db: *const DB,
tz: ?*const tempora.Timezone,
idx: ?Order.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),
projects: std.StringArrayHashMapUnmanaged(Field_Data),

add_another: bool = false,
was_valid: bool = true,
valid: bool = true,
changes_applied: bool = false,
names_changed: bool = false,
created_idx: ?Order.Index = null,

pub const Field = enum {
    id,
    dist,
    po,
    notes,
    total_cost,
    preparing_time,
    waiting_time,
    arrived_time,
    completed_time,
    cancelled_time,
};

const Transaction = @This();

pub fn init_empty(db: *const DB, tz: ?*const tempora.Timezone) Transaction {
    return .{
        .db = db,
        .tz = tz,
        .idx = null,
        .fields = .{
            .id = .{},
            .dist = .{},
            .po = .{},
            .notes = .{},
            .total_cost = .{},
            .preparing_time = .{},
            .waiting_time = .{},
            .arrived_time = .{},
            .completed_time = .{},
            .cancelled_time = .{},
        },
        .projects = .{},
    };
}

pub fn init_idx(db: *const DB, idx: Order.Index, tz: ?*const tempora.Timezone) !Transaction {
    const obj = Order.get(db, idx);

    const project_links = try order.get_sorted_project_links(db, idx);
    var projects: std.StringArrayHashMapUnmanaged(Field_Data) = .{};
    try projects.ensureTotalCapacity(http.temp(), project_links.items.len);

    for (0.., project_links.items) |i, link| {
        const key = try http.tprint("{d}", .{ i });
        projects.putAssumeCapacityNoClobber(key, try Field_Data.init(db, link.prj));
    }

    return .{
        .db = db,
        .tz = tz,
        .idx = idx,
        .fields = try Field_Data.init_fields_ext(Field, db, obj, .{
            .total_cost = if (obj.total_cost_hundreths) |hundreths| try costs.hundreths_to_decimal(http.temp(), hundreths) else "",
            .preparing_time = try timestamps.format_opt_datetime_local(obj.preparing_timestamp_ms, tz),
            .waiting_time = try timestamps.format_opt_datetime_local(obj.waiting_timestamp_ms, tz),
            .arrived_time = try timestamps.format_opt_datetime_local(obj.arrived_timestamp_ms, tz),
            .completed_time = try timestamps.format_opt_datetime_local(obj.completed_timestamp_ms, tz),
            .cancelled_time = try timestamps.format_opt_datetime_local(obj.cancelled_timestamp_ms, tz),
        }),
        .projects = projects,
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

    if (std.mem.startsWith(u8, param.name, "prj_ordering")) {
        return true;
    }

    if (std.mem.startsWith(u8, param.name, "prj")) {
        const index_str = param.name["prj".len..];
        const value = try trim(param.value);

        const gop = try self.projects.getOrPut(http.temp(), index_str);
        if (!gop.found_existing) {
            gop.key_ptr.* = try http.temp().dupe(u8, index_str);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.set_processed(value, self.idx == null);
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
    try self.validate_id();
    try self.validate_dist();
    try self.validate_cost(&self.fields.total_cost);
    try self.validate_time(&self.fields.preparing_time);
    try self.validate_time(&self.fields.waiting_time);
    try self.validate_time(&self.fields.arrived_time);
    try self.validate_time(&self.fields.completed_time);
    try self.validate_time(&self.fields.cancelled_time);

    const project_ids = self.projects.values();
    for (0.., project_ids) |i, *project_id| {
        try self.validate_project(project_id, project_ids[0..i]);
    }
}

fn validate_id(self: *Transaction) !void {
    if (!DB.is_valid_id(self.fields.id.future)) {
        log.debug("Invalid ID: {s}", .{ self.fields.id.future });
        self.fields.id.err = "ID may not be empty or '_', or contain '/'";
        self.fields.id.valid = false;
        self.valid = false;
        return;
    }

    if (Order.maybe_lookup(self.db, self.fields.id.future)) |existing_idx| {
        if (self.idx == null or existing_idx != self.idx) {
            log.debug("Invalid ID (in use): {s}", .{ self.fields.id.future });
            const existing_id = Order.get_id(self.db, existing_idx);
            self.fields.id.err = try http.tprint("In use by <a href=\"/o:{}\" target=\"_blank\">{s}</a>", .{ http.fmtForUrl(existing_id), existing_id });
            self.fields.id.valid = false;
            self.valid = false;
            return;
        }
    }
}

fn validate_dist(self: *Transaction) !void {
    if (self.fields.dist.future.len == 0) return;

    if (Distributor.maybe_lookup(self.db, self.fields.dist.future)) |dist_idx| {
        self.fields.dist.future = Distributor.get_id(self.db, dist_idx);
    } else {
        log.debug("Distributor not found: {s}", .{ self.fields.dist.future });
        self.fields.dist.err = "Distributor not found";
        self.fields.dist.valid = false;
        self.valid = false;
        return;
    }
}

fn validate_cost(self: *Transaction, data: *Field_Data) !void {
    if (data.future.len == 0) return;

    const hundreths = costs.decimal_to_hundreths(data.future) catch {
        log.debug("Invalid cost string: {s}", .{ data.future });
        data.err = try http.tprint("'{s}' is not a valid cost!", .{ data.future });
        data.valid = false;
        self.valid = false;
        return;
    };

    data.future = try costs.hundreths_to_decimal(http.temp(), hundreths);
}

fn validate_time(self: *Transaction, data: *Field_Data) !void {
    if (!try timestamps.validate_opt_datetime_local(data, self.tz)) self.valid = false;
}

fn validate_project(self: *Transaction, data: *Field_Data, prev_project_data: []const Field_Data) !void {
    if (data.future.len == 0) return;

    if (Project.maybe_lookup(self.db, data.future)) |project_idx| {
        data.future = Project.get_id(self.db, project_idx);
    } else {
        log.debug("Project not found: {s}", .{ data.future });
        data.err = "Project not found";
        data.valid = false;
        self.valid = false;
        return;
    }

    for (prev_project_data) |prev_link| {
        if (!prev_link.valid) continue;
        if (!std.mem.eql(u8, data.future, prev_link.future)) continue;
        data.future.len = 0;
    }
}

pub fn apply_changes(self: *Transaction, db: *DB) !void {
    if (!self.valid) return;

    const idx = self.idx orelse {
        const id_str = self.fields.id.future_opt() orelse {
            log.warn("ID not specified", .{});
            return error.BadRequest;
        };

        const idx = try Order.lookup_or_create(db, id_str);

        if (self.fields.dist.future_opt()) |dist| {
            const dist_idx = Distributor.maybe_lookup(db, dist).?;
            try Order.set_dist(db, idx, dist_idx);
        }

        try Order.set_po(db, idx, self.fields.po.future_opt());
        try Order.set_notes(db, idx, self.fields.notes.future_opt());

        if (self.fields.total_cost.future_opt()) |cost| {
            try Order.set_total_cost_hundreths(db, idx, try costs.decimal_to_hundreths(cost));
        }

        try Order.set_preparing_time(db, idx, try timestamps.parse_opt_datetime_local(self.fields.preparing_time.future, self.tz));
        try Order.set_waiting_time(db, idx, try timestamps.parse_opt_datetime_local(self.fields.waiting_time.future, self.tz));
        try Order.set_arrived_time(db, idx, try timestamps.parse_opt_datetime_local(self.fields.arrived_time.future, self.tz));
        try Order.set_completed_time(db, idx, try timestamps.parse_opt_datetime_local(self.fields.completed_time.future, self.tz));
        try Order.set_cancelled_time(db, idx, try timestamps.parse_opt_datetime_local(self.fields.cancelled_time.future, self.tz));

        for (self.projects.values()) |project_id| {
            if (project_id.future.len == 0) continue;
            _ = try Order.Project_Link.lookup_or_create(db, .{
                .order = idx,
                .prj = Project.maybe_lookup(db, project_id.future).?,
            });
        }

        self.changes_applied = true;
        self.created_idx = idx;
        return;
    };

    if (self.fields.id.changed()) |id| {
        try Order.set_id(db, idx, id.future);
        self.changes_applied = true;
    }

    if (self.fields.dist.is_removed()) {
        try Order.set_dist(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.dist.changed()) |dist| {
        const dist_idx = Distributor.maybe_lookup(db, dist.future).?;
        try Order.set_dist(db, idx, dist_idx);
        self.changes_applied = true;
    }

    if (self.fields.po.changed()) |po| {
        try Order.set_po(db, idx, po.future_opt());
        self.changes_applied = true;
    }
    
    if (self.fields.notes.changed()) |notes| {
        try Order.set_notes(db, idx, notes.future_opt());
        self.changes_applied = true;
    }

    if (self.fields.total_cost.is_removed()) {
        try Order.set_total_cost_hundreths(db, idx, null);
        self.changes_applied = true;
    } else if (self.fields.total_cost.changed()) |cost| {
        try Order.set_total_cost_hundreths(db, idx, try costs.decimal_to_hundreths(cost.future));
        self.changes_applied = true;
    }

    if (self.fields.preparing_time.changed()) |time| {
        try Order.set_preparing_time(db, idx, try timestamps.parse_opt_datetime_local(time.future, self.tz));
        self.changes_applied = true;
    }

    if (self.fields.waiting_time.changed()) |time| {
        try Order.set_waiting_time(db, idx, try timestamps.parse_opt_datetime_local(time.future, self.tz));
        self.changes_applied = true;
    }

    if (self.fields.arrived_time.changed()) |time| {
        try Order.set_arrived_time(db, idx, try timestamps.parse_opt_datetime_local(time.future, self.tz));
        self.changes_applied = true;
    }

    if (self.fields.completed_time.changed()) |time| {
        try Order.set_completed_time(db, idx, try timestamps.parse_opt_datetime_local(time.future, self.tz));
        self.changes_applied = true;
    }

    if (self.fields.cancelled_time.changed()) |time| {
        try Order.set_cancelled_time(db, idx, try timestamps.parse_opt_datetime_local(time.future, self.tz));
        self.changes_applied = true;
    }

    var project_ordering: u16 = 0;
    for (self.projects.values()) |project_id| {
        if (project_id.is_changed()) {
            if (project_id.current_opt()) |id| {
                _ = try Order.Project_Link.maybe_remove(db, .{
                    .order = idx,
                    .prj = Project.maybe_lookup(db, id).?,
                });
            }
            if (project_id.future_opt()) |id| {
                const link_idx = try Order.Project_Link.lookup_or_create(db, .{
                    .order = idx,
                    .prj = Project.maybe_lookup(db, id).?,
                });
                try Order.Project_Link.set_order_ordering(db, link_idx, project_ordering);
            }
            self.changes_applied = true;
        }

        if (project_id.future_opt()) |_| project_ordering += 1;
    }
}

pub fn get_post_prefix(db: *const DB, maybe_idx: ?Order.Index) ![]const u8 {
    if (maybe_idx) |idx| {
        const id = Order.get_id(db, idx);
        return try http.tprint("/o:{}", .{ http.fmtForUrl(id) });
    }
    return "/o";
}

const Render_Options = struct {
    target: union (enum) {
        add,
        edit,
        field: Field,
        project: []const u8,
    },
    rnd: ?*std.rand.Xoshiro256,
};

pub fn render_results(self: Transaction, session: ?Session, req: *http.Request, options: Render_Options) !void {
    const post_prefix = try get_post_prefix(self.db, self.created_idx orelse self.idx);

    if (self.changes_applied) {
        if (self.created_idx != null) {
            if (self.add_another) {
                try req.redirect(try http.tprint("/o/add{s}", .{ req.hx_current_query() }), .see_other);
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
            const render_data = .{
                .session = session,
                .validating = true,
                .valid = self.valid,
                .obj = obj,
                .projects = self.projects.values(),
                .title = self.fields.id.future,
                .post_prefix = post_prefix,
                .cancel_url = "/o",
            };
            return switch (options.target) {
                .add => try req.render("order/add.zk", render_data, .{}),
                .edit => try req.render("order/edit.zk", render_data, .{}),
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
                    .post_prefix = post_prefix,
                };
                switch (field) {
                    .id => try req.render("common/post_id.zk", render_data, .{}),
                    .dist => try req.render("order/post_dist.zk", render_data, .{}),
                    .po => try req.render("order/post_po.zk", render_data, .{}),
                    .notes => try req.render("common/post_notes.zk", render_data, .{}),
                    .total_cost => try req.render("order/post_total_cost.zk", render_data, .{}),
                    .preparing_time => try req.render("order/post_preparing_time.zk", render_data, .{}),
                    .waiting_time => try req.render("order/post_waiting_time.zk", render_data, .{}),
                    .arrived_time => try req.render("order/post_arrived_time.zk", render_data, .{}),
                    .completed_time => try req.render("order/post_completed_time.zk", render_data, .{}),
                    .cancelled_time => try req.render("order/post_cancelled_time.zk", render_data, .{}),
                }
            }
        },
        .project => {},
    }

    var project_index: usize = 0;
    for (self.projects.keys(), self.projects.values()) |index_str, data| {
        const is_target = switch (options.target) {
            .project => |target_index| std.mem.eql(u8, index_str, target_index),
            else => false,
        };
        const is_changed = data.is_changed();

        const is_index_changed = if (self.idx != null and index_str.len > 0) is_index_changed: {
            const old_project_index = try std.fmt.parseInt(u16, index_str, 10);
            break :is_index_changed project_index != old_project_index;
        } else false;
        
        if (!is_target and !is_changed and !is_index_changed) {
            project_index += 1;
            continue;
        }
        
        var new_index_buf: [32]u8 = undefined;
        var new_index: []const u8 = if (is_index_changed) try http.tprint("{d}", .{ project_index }) else index_str;
        var is_placeholder = true;

        if (index_str.len > 0) {
            if (data.future.len == 0) {
                if (is_target) {
                    _ = try req.response();
                } else {
                    try req.render("order/post_project.zk", .{
                        .index = index_str,
                        .swap_oob = "delete",
                    }, .{});
                }
                continue;
            }
            project_index += 1;
            is_placeholder = false;
        } else if (data.future.len > 0 and data.valid) {
            if (options.rnd) |rnd| {
                var buf: [16]u8 = undefined;
                rnd.fill(&buf);
                const Base64 = std.base64.url_safe_no_pad.Encoder;
                new_index = Base64.encode(&new_index_buf, &buf);
            } else {
                new_index = try std.fmt.bufPrint(&new_index_buf, "{d}", .{ self.projects.count() - 1 });
            }
            is_placeholder = false;
        }

        const render_data = .{
            .saved = self.changes_applied and is_changed,
            .valid = data.valid,
            .err = data.err,
            .post_prefix = post_prefix,
            .index = if (is_placeholder) null else new_index,
            .swap_oob = if (is_target) null else try http.tprint("outerHTML:#prj{s}", .{ index_str }),

            .prj_id = data.future,
            .err_prj = !data.valid,
        };

        if (is_placeholder) {
            try req.render("order/post_project_placeholder.zk", render_data, .{});
        } else {
            try req.render("order/post_project.zk", render_data, .{});
            if (index_str.len == 0) {
                try req.render("order/post_project_placeholder.zk", .{
                    .post_prefix = post_prefix,
                }, .{});
            }
        }
    }
}

const log = std.log.scoped(.@"http.order");

const Order = DB.Order;
const Distributor = DB.Distributor;
const Project = DB.Project;
const DB = @import("../../DB.zig");
const order = @import("../order.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const costs = @import("../../costs.zig");
const timestamps = @import("../timestamps.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
