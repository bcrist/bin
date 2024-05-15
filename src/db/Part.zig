
id: []const u8,
full_name: ?[]const u8,
parent_id: ?[]const u8,
manufacturer_id: ?[]const u8,
package_id: ?[]const u8,
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

pub const Index = enum (u32) { _ };

const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
