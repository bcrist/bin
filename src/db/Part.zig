
id: []const u8,
full_name: ?[]const u8,
parent: ?Index,
manufacturer: ?Manufacturer.Index,
package: ?Package.Index,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,

// ancestors
// children
// descendents
// inventories
// distributor part numbers
// Attachments/Images/Datasheets/3D models/footprints
// Parameters - pin count, pin pitch, bounding dimensions, body dimensions
// Parameters expected for children
// Tags - lead free

const Part = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Part;
};


const Package = @import("Package.zig");
const Manufacturer = @import("Manufacturer.zig");
const std = @import("std");
