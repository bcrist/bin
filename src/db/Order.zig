id: []const u8,
dist: ?Distributor.Index,
po: ?[]const u8,
notes: ?[]const u8,
total_cost_hundreths: ?i32,
preparing_timestamp_ms: ?i64,
waiting_timestamp_ms: ?i64,
arrived_timestamp_ms: ?i64,
completed_timestamp_ms: ?i64,
cancelled_timestamp_ms: ?i64,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,

// Attachments/Images
// Tags

const Order = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Order;
    
    pub inline fn init(i: usize) Index {
        const raw_i: u32 = @intCast(i);
        return @enumFromInt(raw_i);
    }

    pub inline fn any(self: Index) DB.Any_Index {
        return DB.Any_Index.init(self);
    }

    pub inline fn raw(self: Index) u32 {
        return @intFromEnum(self);
    }
};

// pub const Project_Link = struct {
//     order: Index,
//     prj: Project.Index,
// };

pub const Status = enum {
    none,
    preparing,
    waiting,
    arrived,
    completed,
    cancelled,

    pub fn display(self: Status) []const u8 {
        return switch (self) {
            .none => "None/BOM",
            .preparing => "Preparing",
            .waiting => "Waiting",
            .arrived => "Arrived",
            .completed => "Completed",
            .cancelled => "Cancelled",
        };
    }
};

pub fn init_empty(id: []const u8, timestamp_ms: i64) Order {
    return .{
        .id = id,
        .dist = null,
        .po = null,
        .notes = null,
        .total_cost_hundreths = null,
        .preparing_timestamp_ms = null,
        .waiting_timestamp_ms = null,
        .arrived_timestamp_ms = null,
        .completed_timestamp_ms = null,
        .cancelled_timestamp_ms = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
    };
}

pub fn maybe_lookup(db: *const DB, possible_id: ?[]const u8) ?Index {
    if (possible_id) |id| {
        if (db.order_lookup.get(id)) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, id: []const u8) !Index {
    if (db.order_lookup.get(id)) |idx| return idx;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;
    
    const idx = Index.init(db.orders.len);
    const now = std.time.milliTimestamp();
    const order = init_empty(try db.intern(id), now);
    try db.orders.append(db.container_alloc, order);
    try db.order_lookup.putNoClobber(db.container_alloc, order.id, idx);
    try db.mark_dirty(idx);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Order {
    return db.orders.get(idx.raw());
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.orders.items(.id)[idx.raw()];
}

pub fn get_status(self: Order) Status {
    return if (self.cancelled_timestamp_ms != null) .cancelled
        else if (self.completed_timestamp_ms != null) .completed
        else if (self.arrived_timestamp_ms != null) .arrived
        else if (self.waiting_timestamp_ms != null) .waiting
        else if (self.preparing_timestamp_ms != null) .preparing
        else .none;
}

pub fn delete(db: *DB, idx: Index) !void {
    // TODO remove project links referencing this
    // TODO remove order items

    const i = idx.raw();
    std.debug.assert(db.order_lookup.remove(db.orders.items(.id)[i]));

    db.orders.set(i, init_empty("", std.time.milliTimestamp()));
    try db.mark_dirty(idx);
}

pub fn set_id(db: *DB, idx: Index, id: []const u8) !void {
    const i = idx.raw();
    const ids = db.orders.items(.id);
    const old_id = ids[i];
    if (std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.order_lookup.remove(old_id));
    try db.order_lookup.putNoClobber(db.container_alloc, new_id, idx);
    ids[i] = new_id;
    try set_modified(db, idx);

    if (db.loading) return;

    // TODO mark dirty any projects referencing this order
}

pub fn set_dist(db: *DB, idx: Index, dist: ?Distributor.Index) !void {
    return set_optional(Distributor.Index, db, idx, .dist, dist);
}

pub fn set_po(db: *DB, idx: Index, po: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .po, po);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_total_cost_hundreths(db: *DB, idx: Index, cost: ?i32) !void {
    return set_optional(i32, db, idx, .total_cost_hundreths, cost);
}

pub fn set_preparing_time(db: *DB, idx: Index, ts: ?i64) !void {
    return set_optional(i64, db, idx, .preparing_timestamp_ms, ts);
}

pub fn set_waiting_time(db: *DB, idx: Index, ts: ?i64) !void {
    return set_optional(i64, db, idx, .waiting_timestamp_ms, ts);
}

pub fn set_arrived_time(db: *DB, idx: Index, ts: ?i64) !void {
    return set_optional(i64, db, idx, .arrived_timestamp_ms, ts);
}

pub fn set_completed_time(db: *DB, idx: Index, ts: ?i64) !void {
    return set_optional(i64, db, idx, .completed_timestamp_ms, ts);
}

pub fn set_cancelled_time(db: *DB, idx: Index, ts: ?i64) !void {
    return set_optional(i64, db, idx, .cancelled_timestamp_ms, ts);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const created_timestamps = db.orders.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    try set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const modified_timestamps = db.orders.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    try db.mark_dirty(idx);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Order, idx, field, T, raw);
}

fn set_modified(db: *DB, idx: Index) !void {
    try db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const Distributor = DB.Distributor;
// const Project = DB.Project;
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
