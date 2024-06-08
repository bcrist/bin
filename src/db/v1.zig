pub fn parse_data(db: *DB, reader: *sx.Reader) !void {
    const parsed = try reader.require_object(reader.token.allocator, SX_Data, SX_Data.context);
    for (parsed.mfr) |item| try item.read(db);
    for (parsed.loc) |item| try item.read(db);
    for (parsed.pkg) |item| try item.read(db);
}

pub fn write_data(db: *DB, root: *std.fs.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var filenames = paths.StringHashSet.init(arena.allocator());
    try SX_Manufacturer.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();
    try SX_Location.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();
    try SX_Package.write_dirty(arena.allocator(), db, root, &filenames);
}

const SX_Data = struct {
    mfr: []SX_Manufacturer = &.{},
    loc: []SX_Location = &.{},
    pkg: []SX_Package = &.{},

    pub const context = struct {
        pub const mfr = SX_Manufacturer.context;
        pub const loc = SX_Location.context;
        pub const pkg = SX_Package.context;
    };
};

const SX_Manufacturer = @import("v1/SX_Manufacturer.zig");
const SX_Location = @import("v1/SX_Location.zig");
const SX_Package = @import("v1/SX_Package.zig");

const log = std.log.scoped(.db);

const DB = @import("../DB.zig");
const paths = @import("paths.zig");
const sx = @import("sx");
const std = @import("std");
