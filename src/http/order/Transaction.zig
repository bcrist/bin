db: *const DB,
tz: ?*const tempora.Timezone,
idx: ?Order.Index,

fields: std.enums.EnumFieldStruct(Field, Field_Data, null),

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
    };
}

pub fn init_idx(db: *const DB, idx: Order.Index, tz: ?*const tempora.Timezone) !Transaction {
    const order = Order.get(db, idx);
    return .{
        .db = db,
        .tz = tz,
        .idx = idx,
        .fields = try Field_Data.init_fields_ext(Field, db, order, .{
            .total_cost = if (order.total_cost_hundreths) |hundreths| try costs.hundreths_to_decimal(http.temp(), hundreths) else "",
            .preparing_time = try timestamps.format_opt_datetime_local(order.preparing_timestamp_ms, tz),
            .waiting_time = try timestamps.format_opt_datetime_local(order.waiting_timestamp_ms, tz),
            .arrived_time = try timestamps.format_opt_datetime_local(order.arrived_timestamp_ms, tz),
            .completed_time = try timestamps.format_opt_datetime_local(order.completed_timestamp_ms, tz),
            .cancelled_time = try timestamps.format_opt_datetime_local(order.cancelled_timestamp_ms, tz),
        }),
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
    try self.validate_id();
    try self.validate_dist();
    try self.validate_cost(&self.fields.total_cost);
    try self.validate_time(&self.fields.preparing_time);
    try self.validate_time(&self.fields.waiting_time);
    try self.validate_time(&self.fields.arrived_time);
    try self.validate_time(&self.fields.completed_time);
    try self.validate_time(&self.fields.cancelled_time);
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
    }
}

const log = std.log.scoped(.@"http.order");

const Order = DB.Order;
const Distributor = DB.Distributor;
const DB = @import("../../DB.zig");
const Field_Data = @import("../Field_Data.zig");
const Session = @import("../../Session.zig");
const costs = @import("../../costs.zig");
const timestamps = @import("../timestamps.zig");
const Query_Param = http.Query_Iterator.Query_Param;
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
