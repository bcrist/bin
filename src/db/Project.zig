
id: []const u8,
full_name: []const u8,
notes: []const u8,
created: Date_Time,
modified: Date_Time,
completed: ?Date_Time,

// Attachments/Images
// Tags

pub const Index = enum (u32) { _ };

const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
