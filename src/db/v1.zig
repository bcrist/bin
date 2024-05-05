pub fn parse_data(db: *DB, reader: *sx.Reader) !void {
    const parsed = try reader.require_object(reader.token.allocator, SX_Data, SX_Data.context);
    for (parsed.mfr) |item| try item.read(db);
}

pub fn write_data(db: *DB, root: *std.fs.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var filenames = paths.StringHashSet.init(arena.allocator());

    try write_manufacturers(arena.allocator(), db, root, &filenames);

    db.dirty_timestamp_ms = null;
}

fn write_manufacturers(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.mfrs.len));
    defer filenames.clearRetainingCapacity();

    const dirty_timestamp_ms = db.dirty_timestamp_ms orelse std.time.milliTimestamp();
    const ids = db.mfrs.items(.id);

    var dir = try root.makeOpenPath("mfr", .{ .iterate = true });
    defer dir.close();

    for (0..db.mfrs.len, db.mfrs.items(.modified_timestamp_ms)) |i, modified_ts| {
        const dest_path = try paths.unique_path(allocator, ids[i], filenames);
        
        if (modified_ts < dirty_timestamp_ms) continue;

        log.info("Writing mfr{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("mfr");
        try sxw.object(try SX_Manufacturer.init(allocator, db, @enumFromInt(i)), SX_Manufacturer.context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "mfr" ++ std.fs.path.sep_str);
}


const SX_Data = struct {
    mfr: []SX_Manufacturer = &.{},

    pub const context = struct {
        pub const mfr = SX_Manufacturer.context;
    };
};


const SX_Manufacturer = @import("v1/SX_Manufacturer.zig");

const log = std.log.scoped(.db);

const DB = @import("../DB.zig");
const paths = @import("paths.zig");
const sx = @import("sx");
const std = @import("std");
