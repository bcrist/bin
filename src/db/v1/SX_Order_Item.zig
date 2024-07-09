ordering: u32 = 0,
mfr: ?[]const u8 = null,
part: ?[]const u8 = null,
qty: ?i32 = null,
qty_uncertainty: ?Order_Item.Quantity_Uncertainty = null,
loc: ?[]const u8 = null,
each: ?[]const u8 = null,
total: ?[]const u8 = null,
notes: ?[]const u8 = null,

const SX_Order_Item = @This();

pub const context = struct {
    pub const inline_fields = &.{ "mfr", "part", "qty", "qty_uncertainty" };
    pub const qty = "d:0>1"; // ensure '+' prefix is used for positive quantities
    pub const ordering = void;
    pub const compact = struct {
        pub const loc = true;
        pub const each = true;
        pub const total = true;
        pub const notes = true;
    };
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Order_Item.Index) !SX_Order_Item {
    const data = Order_Item.get(db, idx);

    var mfr_str: ?[]const u8 = null;
    var part_str: ?[]const u8 = null;

    if (data.part) |part_idx| {
        part_str = Part.get_id(db, part_idx);
        if (Part.get_mfr(db, part_idx)) |mfr_idx| {
            mfr_str = Manufacturer.get_id(db, mfr_idx);
        }
    }

    const loc_str = if (data.loc) |loc_idx| Location.get_id(db, loc_idx) else null;

    if (data.qty != null and part_str == null) part_str = "_";
    if (part_str != null and mfr_str == null) mfr_str = "_";

    const cost_each_str = if (data.cost_each_hundreths) |cost| try costs.hundreths_to_decimal(temp, cost) else null;
    const cost_total_str = if (data.cost_total_hundreths) |cost| try costs.hundreths_to_decimal(temp, cost) else null;

    return .{
        .mfr = mfr_str,
        .part = part_str,
        .qty = data.qty,
        .qty_uncertainty = data.qty_uncertainty,
        .loc = loc_str,
        .each = cost_each_str,
        .total = cost_total_str,
        .notes = data.notes,
    };
}

pub fn read(self: SX_Order_Item, db: *DB, order: Order.Index, ordering: usize) !void {
    var mfr_idx: ?Manufacturer.Index = null;
    if (self.mfr) |mfr_id| {
        if (mfr_id.len > 0 and !std.mem.eql(u8, mfr_id, "_")) {
            mfr_idx = try Manufacturer.lookup_or_create(db, mfr_id);
        }
    }

    var part_idx: ?Part.Index = null;
    if (self.part) |part_id| {
        if (part_id.len > 0 and !std.mem.eql(u8, part_id, "_")) {
            part_idx = try Part.lookup_or_create(db, mfr_idx, part_id);
        }
    }

    const loc_idx = if (self.loc) |loc_id| try Location.lookup_or_create(db, loc_id) else null;
    const cost_each = if (self.each) |cost| try costs.decimal_to_hundreths(cost) else null;
    const cost_total = if (self.total) |cost| try costs.decimal_to_hundreths(cost) else null;

    _ = try Order_Item.create(db, .{
        .order = order,
        .ordering = @intCast(ordering),
        .part = part_idx,
        .qty = self.qty,
        .qty_uncertainty = self.qty_uncertainty,
        .loc = loc_idx,
        .cost_each_hundreths = cost_each,
        .cost_total_hundreths = cost_total,
        .notes = self.notes,
    });
}

pub fn less_than(_: void, a: SX_Order_Item, b: SX_Order_Item) bool {
    return a.ordering < b.ordering;
}

const Order = DB.Order;
const Part = DB.Part;
const Location = DB.Location;
const Manufacturer = DB.Manufacturer;
const Order_Item = DB.Order_Item;
const DB = @import("../../DB.zig");
const costs = @import("../../costs.zig");
const std = @import("std");
