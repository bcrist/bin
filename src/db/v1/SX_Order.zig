id: []const u8 = "",
dist: ?[]const u8 = null,
po: ?[]const u8 = null,
notes: ?[]const u8 = null,
total: ?[]const u8 = null,
preparing: ?Date_Time.With_Offset = null,
waiting: ?Date_Time.With_Offset = null,
arrived: ?Date_Time.With_Offset = null,
completed: ?Date_Time.With_Offset = null,
cancelled: ?Date_Time.With_Offset = null,
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const SX_Order = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id" };
    pub const preparing = Date_Time.With_Offset.fmt_sql;
    pub const waiting = Date_Time.With_Offset.fmt_sql;
    pub const arrived = Date_Time.With_Offset.fmt_sql;
    pub const completed = Date_Time.With_Offset.fmt_sql;
    pub const cancelled = Date_Time.With_Offset.fmt_sql;
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Order.Index) !SX_Order {
    const data = Order.get(db, idx);

    const total_cost_str = if (data.total_cost_hundreths) |cost| total_cost_str: {
        const cost_int = @divTrunc(cost, 100);
        const cost_cents = @mod(cost, 100);
        break :total_cost_str try std.fmt.allocPrint(temp, "{d}.{d:0>2}", .{ cost_int, cost_cents });
    } else null;

    return .{
        .id = data.id,
        .dist = if (data.dist) |dist_idx| Distributor.get_id(db, dist_idx) else null,
        .po = data.po,
        .notes = data.notes,
        .total = total_cost_str,
        .preparing = if (data.preparing_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .waiting = if (data.waiting_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .arrived = if (data.arrived_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .completed = if (data.complete_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .cancelled = if (data.cancelled_timestamp_ms) |ts| Date_Time.With_Offset.from_timestamp_ms(ts, null) else null,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Order, db: *DB) !void {
    const id = std.mem.trim(u8, self.id, &std.ascii.whitespace);
    const idx = try Order.lookup_or_create(db, id);

    try Order.set_id(db, idx, id);
    if (self.dist) |dist_id| {
        try Order.set_dist(db, idx, try Distributor.lookup_or_create(db, dist_id));
    }
    if (self.po) |po| try Order.set_po(db, idx, po);
    if (self.notes) |notes| try Order.set_notes(db, idx, notes);
    if (self.total) |cost_str| {
        const total_cost_hundreths: i32 = if (std.mem.indexOfScalar(u8, cost_str, '.')) |decimal_pos| total_cost: {
            const int: i32 = try std.fmt.parseInt(i25, cost_str[0..decimal_pos], 10);
            const cents: i32 = try std.fmt.parseInt(i8, cost_str[decimal_pos + 1 ..], 10);
            break :total_cost int * 100 + cents;
        } else 100 * try std.fmt.parseInt(i25, cost_str, 10);
        try Order.set_total_cost_hundreths(db, idx, total_cost_hundreths);
    }
    if (self.preparing) |dto| try Order.set_preparing_time(db, idx, dto.timestamp_ms());
    if (self.waiting) |dto| try Order.set_waiting_time(db, idx, dto.timestamp_ms());
    if (self.arrived) |dto| try Order.set_arrived_time(db, idx, dto.timestamp_ms());
    if (self.completed) |dto| try Order.set_complete_time(db, idx, dto.timestamp_ms());
    if (self.cancelled) |dto| try Order.set_cancelled_time(db, idx, dto.timestamp_ms());
    if (self.created) |dto| try Order.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Order.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.orders.len));
    defer filenames.clearRetainingCapacity();

    var dir = try root.makeOpenPath("o", .{ .iterate = true });
    defer dir.close();

    // TODO group by preparing or created date

    for (0.., db.orders.items(.id)) |i, id| {
        const dest_path = try paths.unique_path(allocator, id, filenames);
        const idx = Order.Index.init(i);

        if (!db.dirty_set.contains(idx.any())) continue;

        log.info("Writing o{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("o");
        try sxw.object(try init(allocator, db, idx), context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "o" ++ std.fs.path.sep_str);
}

const log = std.log.scoped(.db);

const Order = DB.Order;
const Distributor = DB.Distributor;
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
