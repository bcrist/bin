order: ?Order.Index, // set to null when deleting
ordering: u32,
part: ?Part.Index,
qty: ?i32,
loc: ?Location.Index,
cost_each_hundreths: ?i32,
cost_total_hundreths: ?i32,
notes: ?[]const u8,

const Order_Item = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Order_Item;
    
    pub inline fn init(i: usize) Index {
        const raw_i: u32 = @intCast(i);
        return @enumFromInt(raw_i);
    }

    pub inline fn raw(self: Index) u32 {
        return @intFromEnum(self);
    }

    pub fn less_than_assume_same_order(db: *const DB, a: Index, b: Index) bool {
        const ordering = db.order_items.items(.ordering);
        return ordering[a.raw()] < ordering[b.raw()];
    }
};

pub fn init_empty() Order_Item {
    return .{
        .order = null,
        .ordering = 0xFFFFFFFF,
        .part = null,
        .qty = null,
        .loc = null,
        .cost_each_hundreths = null,
        .cost_total_hundreths = null,
        .notes = null,
    };
}

pub fn create(db: *DB, item: Order_Item) !Index {
    const final_item: Order_Item = .{
        .order = item.order orelse return error.InvalidOrderItem,
        .ordering = item.ordering,
        .part = item.part,
        .qty = item.qty,
        .loc = item.loc,
        .cost_each_hundreths = item.cost_each_hundreths,
        .cost_total_hundreths = item.cost_total_hundreths,
        .notes = try db.maybe_intern(item.notes),
    };

    const idx = Index.init(db.order_items.len);
    try db.order_items.append(db.container_alloc, final_item);
    try db.maybe_set_modified(final_item.order.?);
    try db.mark_dirty(idx);
    if (item.part) |part_idx| try db.mark_dirty(part_idx);
    if (item.loc) |loc_idx| try db.mark_dirty(loc_idx);
    // TODO invalidate any caches of Order Items or stock amonuts that might need to include this
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Order_Item {
    return db.order_items.get(idx.raw());
}

pub inline fn get_order(db: *const DB, idx: Index) !Order.Index {
    return db.order_items.items(.order)[idx.raw()] orelse error.InvalidOrderItem;
}

pub inline fn get_part(db: *const DB, idx: Index) ?Part.Index {
    return db.order_items.items(.part)[idx.raw()];
}

pub inline fn get_loc(db: *const DB, idx: Index) ?Location.Index {
    return db.order_items.items(.loc)[idx.raw()];
}

pub fn delete(db: *DB, idx: Index) !void {
    const item = db.order_items.get(idx.raw());
    if (item.order) |order_idx| try Order.set_modified(db, order_idx);
    if (item.part) |part_idx| try db.mark_dirty(part_idx);
    if (item.loc) |loc_idx| try db.mark_dirty(loc_idx);
    db.order_items.set(idx.raw(), init_empty());
    // TODO invalidate any caches of Order Items or stock amonuts that might need to include this
}

pub fn delete_all_for_order(db: *DB, order: Order.Index) !void {
    var deleted_at_least_one = false;
    const parts = db.order_items.items(.part);
    const locs = db.order_items.items(.loc);
    for (0.., db.order_items.items(.order)) |i, item_order_idx| {
        if (item_order_idx == order) {
            if (parts[i]) |part_idx| try db.mark_dirty(part_idx);
            if (locs[i]) |loc_idx| try db.mark_dirty(loc_idx);
            db.order_items.set(i, init_empty());
            deleted_at_least_one = true;
            // TODO invalidate any caches of Order Items or stock amonuts that might need to include this
        }
    }
    if (deleted_at_least_one) {
        try Order.set_modified(db, order);
    }
}

pub fn set_order(db: *DB, idx: Index, order_idx: Order.Index) !void {
    const i = idx.raw();
    const orders = db.order_items.items(.order);
    if (order_idx == orders[i]) return;
    orders[i] = order_idx;
    try Order.set_modified(db, order_idx);
}

pub fn set_ordering(db: *DB, idx: Index, ordering: u32) !void {
    const order_idx = try get_order(db, idx);
    const i = idx.raw();
    const orderings = db.order_items.items(.ordering);
    if (ordering == orderings[i]) return;
    orderings[i] = ordering;
    try Order.set_modified(db, order_idx);
}

pub fn set_part(db: *DB, idx: Index, maybe_part_idx: ?Part.Index) !void {
    const order_idx = try get_order(db, idx);
    const old_part_idx = db.order_items.items(.part)[idx.raw()];
    if (try db.set_optional(Order, idx, .part, Part.Index, maybe_part_idx)) {
        if (old_part_idx) |part_idx| try db.mark_dirty(part_idx);
        if (maybe_part_idx) |part_idx| try db.mark_dirty(part_idx);
        try Order.set_modified(db, order_idx);
    }
}

pub fn set_qty(db: *DB, idx: Index, qty: ?i32) !void {
    const order_idx = try get_order(db, idx);
    if (try db.set_optional(Order, idx, .qty, i32, qty)) {
        if (get_part(db, idx)) |part_idx| try db.mark_dirty(part_idx);
        if (get_loc(db, idx)) |loc_idx| try db.mark_dirty(loc_idx);
        try Order.set_modified(db, order_idx);
    }
}

pub fn set_loc(db: *DB, idx: Index, maybe_loc_idx: ?Location.Index) !void {
    const order_idx = try get_order(db, idx);
    const old_loc_idx = db.order_items.items(.loc)[idx.raw()];
    if (try db.set_optional(Order, idx, .loc, Location.Index, maybe_loc_idx)) {
        if (old_loc_idx) |loc_idx| try db.mark_dirty(loc_idx);
        if (maybe_loc_idx) |loc_idx| try db.mark_dirty(loc_idx);
        try Order.set_modified(db, order_idx);
    }
}

pub fn set_cost_each_hundreths(db: *DB, idx: Index, each: ?i32) !void {
    try set_optional(i32, db, idx, .cost_each_hundreths, each);
}

pub fn set_cost_total_hundreths(db: *DB, idx: Index, total: ?i32) !void {
    try set_optional(i32, db, idx, .cost_total_hundreths, total);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    try set_optional([]const u8, db, idx, .notes, notes);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    const order_idx = try get_order(db, idx);
    if (try db.set_optional(Order, idx, field, T, raw)) {
        try Order.set_modified(db, order_idx);
    }
}

const log = std.log.scoped(.db);

const Order = DB.Order;
const Part = DB.Part;
const Location = DB.Location;
const DB = @import("../DB.zig");
const std = @import("std");
