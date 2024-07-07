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
    try Order_Item.delete_all_for_order(db, idx);

    const prj_links = db.prj_order_links.keys();
    var prj_link_i = prj_links.len;
    while (prj_link_i > 0) {
        prj_link_i -= 1;
        const link = prj_links[prj_link_i];
        if (link.order == idx) {
            try Project.set_modified(db, link.prj);
            db.prj_order_links.swapRemoveAt(prj_link_i);
        }
    }

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

    for (db.prj_order_links.keys()) |link| {
        if (link.order == idx) {
            try db.mark_dirty(link.prj);
        }
    }
}

pub fn set_dist(db: *DB, idx: Index, maybe_dist_idx: ?Distributor.Index) !void {
    // If we wanted to list orders in the distributor .sx files, we'd need to uncomment this:
    //const old_dist_idx = db.orders.items(.dist)[idx.raw()];
    if (try db.set_optional(Order, idx, .dist, Distributor.Index, maybe_dist_idx)) {
        //if (old_dist_idx) |dist_idx| try db.mark_dirty(dist_idx);
        //if (maybe_dist_idx) |dist_idx| try db.mark_dirty(dist_idx);
    }
}

pub fn set_po(db: *DB, idx: Index, po: ?[]const u8) !void {
    try set_optional([]const u8, db, idx, .po, po);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    try set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_total_cost_hundreths(db: *DB, idx: Index, cost: ?i32) !void {
    try set_optional(i32, db, idx, .total_cost_hundreths, cost);
}

pub fn set_preparing_time(db: *DB, idx: Index, ts: ?i64) !void {
    try set_optional(i64, db, idx, .preparing_timestamp_ms, ts);
}

pub fn set_waiting_time(db: *DB, idx: Index, ts: ?i64) !void {
    try set_optional(i64, db, idx, .waiting_timestamp_ms, ts);
}

pub fn set_arrived_time(db: *DB, idx: Index, ts: ?i64) !void {
    try set_optional(i64, db, idx, .arrived_timestamp_ms, ts);
}

pub fn set_completed_time(db: *DB, idx: Index, ts: ?i64) !void {
    try set_optional(i64, db, idx, .completed_timestamp_ms, ts);
}

pub fn set_cancelled_time(db: *DB, idx: Index, ts: ?i64) !void {
    try set_optional(i64, db, idx, .cancelled_timestamp_ms, ts);
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
    _ = try db.set_optional(Order, idx, field, T, raw);
}

pub fn set_modified(db: *DB, idx: Index) !void {
    try db.maybe_set_modified(idx);
}

pub const Project_Link = struct {
    order: Order.Index,
    prj: Project.Index,
    order_ordering: u16,
    prj_ordering: u16,

    pub const Index = enum (u32) {
        _,

        pub inline fn init(i: usize) Project_Link.Index {
            const raw_i: u32 = @intCast(i);
            return @enumFromInt(raw_i);
        }

        pub inline fn raw(self: Project_Link.Index) u32 {
            return @intFromEnum(self);
        }
    };

    pub const hash_context = struct {
        pub fn hash(_: hash_context, k: Project_Link) u32 {
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hasher, k.order);
            std.hash.autoHash(&hasher, k.prj);
            return @truncate(hasher.final());
        }
    
        pub fn eql(_: hash_context, k: Project_Link, other: Project_Link, index: usize) bool {
            _ = index;
            return k.order == other.order and k.prj == other.prj;
        }
    };

    pub const Lookup = struct {
        order: Order.Index,
        prj: Project.Index,

        pub const hash_context = struct {
            pub fn hash(_: @This(), k: Lookup) u32 {
                var hasher = std.hash.Wyhash.init(0);
                std.hash.autoHash(&hasher, k.order);
                std.hash.autoHash(&hasher, k.prj);
                return @truncate(hasher.final());
            }
        
            pub fn eql(_: @This(), k: Lookup, other: Project_Link, index: usize) bool {
                _ = index;
                return k.order == other.order and k.prj == other.prj;
            }
        };
    };

    pub fn lookup_or_create(db: *DB, lookup: Lookup) !Project_Link.Index {
        const result = try db.prj_order_links.getOrPutAdapted(db.container_alloc, lookup, Lookup.hash_context{});
        if (!result.found_existing) {
            var order_ordering: u16 = 0;
            var prj_ordering: u16 = 0;
            for (db.prj_order_links.keys()) |link| {
                if (link.order == lookup.order) order_ordering += 1;
                if (link.prj == lookup.prj) prj_ordering += 1;
            }

            result.key_ptr.* = .{
                .order = lookup.order,
                .prj = lookup.prj,
                .order_ordering = order_ordering,
                .prj_ordering = prj_ordering
            };

            try Order.set_modified(db, lookup.order);
            try Project.set_modified(db, lookup.prj);
        }
        return Project_Link.Index.init(result.index);
    }

    pub fn maybe_remove(db: *DB, lookup: Lookup) !bool {
        if (db.prj_order_links.swapRemoveAdapted(lookup, Lookup.hash_context{})) {
            try Order.set_modified(db, lookup.order);
            try Project.set_modified(db, lookup.prj);
            return true;
        }
        return false;
    }

    pub inline fn get(db: *DB, idx: Project_Link.Index) Project_Link {
        return db.prj_order_links.keys()[idx.raw()];
    }

    pub fn set_order_ordering(db: *DB, idx: Project_Link.Index, ordering: u16) !void {
        const i = idx.raw();
        const link = db.prj_order_links.keys()[i];
        if (link.order_ordering == ordering) return;
        db.prj_order_links.keys()[i].order_ordering = ordering;
        try Order.set_modified(db, link.order);
    }

    pub fn set_prj_ordering(db: *DB, idx: Project_Link.Index, ordering: u16) !void {
        const i = idx.raw();
        const link = db.prj_order_links.keys()[i];
        if (link.prj_ordering == ordering) return;
        db.prj_order_links.keys()[i].prj_ordering = ordering;
        try Project.set_modified(db, link.prj);
    }

    pub fn order_less_than(_: void, a: Project_Link, b: Project_Link) bool {
        return a.order_ordering < b.order_ordering;
    }

    pub fn prj_less_than(_: void, a: Project_Link, b: Project_Link) bool {
        return a.prj_ordering < b.prj_ordering;
    }
};

const log = std.log.scoped(.db);

const Order_Item = DB.Order_Item;
const Distributor = DB.Distributor;
const Project = DB.Project;
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
