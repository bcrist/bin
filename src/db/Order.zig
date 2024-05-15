
id: []const u8,
full_name: ?[]const u8,
project_id: ?[]const u8,
distributor_id: ?[]const u8,
distributor_po: ?[]const u8,
notes: ?[]const u8,
created: Date_Time,
modified: Date_Time,
submitted: ?Date_Time,
received: ?Date_Time,

// stock changes
// misc costs
// Attachments/Images
// Tags

pub const Index = enum (u32) { _ };

const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
