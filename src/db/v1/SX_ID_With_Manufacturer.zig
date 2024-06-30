mfr: []const u8 = "_",
id: []const u8 = "",

pub const context = struct {
    pub const inline_fields = &.{ "mfr", "id" };
};

const SX_ID_With_Manufacturer = @This();

pub fn get_mfr_idx(self: SX_ID_With_Manufacturer, db: *DB) !?Manufacturer.Index {
    if (self.mfr.len == 0 or std.mem.eql(u8, self.mfr, "_")) return null;
    return try Manufacturer.lookup_or_create(db, self.mfr);
}

const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const std = @import("std");
