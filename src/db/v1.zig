pub fn parse_data(db: *DB, reader: *sx.Reader) !void {
    const parsed = try reader.require_object(reader.token.allocator, SX_Data, SX_Data.context);
    for (parsed.order) |item| try item.read(db); // read orders first to avoid unneccessary calls to Order_Item.delete_all_for_order
    for (parsed.part) |item| try item.read(db);
    for (parsed.loc) |item| try item.read(db);
    for (parsed.mfr) |item| try item.read(db);
    for (parsed.pkg) |item| try item.read(db);
    for (parsed.prj) |item| try item.read(db);
    for (parsed.dist) |item| try item.read(db);
}

pub fn write_data(db: *DB, root: *std.fs.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var filenames = paths.StringHashSet.init(arena.allocator());

    try SX_Part.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();

    try SX_Location.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();

    try SX_Manufacturer.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();

    try SX_Package.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();

    try SX_Distributor.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();
    
    try SX_Project.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();

    try SX_Order.write_dirty(arena.allocator(), db, root, &filenames);
    filenames.clearRetainingCapacity();

    // TODO arena stats
}

const SX_Data = struct {
    mfr: []SX_Manufacturer = &.{},
    dist: []SX_Distributor = &.{},
    loc: []SX_Location = &.{},
    pkg: []SX_Package = &.{},
    part: []SX_Part = &.{},
    prj: []SX_Project = &.{},
    order: []SX_Order = &.{},

    pub const context = struct {
        pub const mfr = SX_Manufacturer.context;
        pub const dist = SX_Distributor.context;
        pub const loc = SX_Location.context;
        pub const pkg = SX_Package.context;
        pub const part = SX_Part.context;
        pub const prj = SX_Project.context;
        pub const order = SX_Order.context;
    };
};

const SX_Manufacturer = @import("v1/SX_Manufacturer.zig");
const SX_Distributor = @import("v1/SX_Distributor.zig");
const SX_Location = @import("v1/SX_Location.zig");
const SX_Package = @import("v1/SX_Package.zig");
const SX_Part = @import("v1/SX_Part.zig");
const SX_Project = @import("v1/SX_Project.zig");
const SX_Order = @import("v1/SX_Order.zig");

const log = std.log.scoped(.db);

const DB = @import("../DB.zig");
const paths = @import("paths.zig");
const sx = @import("sx");
const std = @import("std");
