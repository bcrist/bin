
id: []const u8,
full_name: []const u8,
parent_id: ?[]const u8,
notes: []const u8,
created: Date_Time,
modified: Date_Time,

// ancestors
// children
// descendents
// dimensions (rows/columns)
// inventories
// Attachments/Images
// Tags - lead free

pub const Index = enum (u32) { _ };

const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
