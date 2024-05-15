
id: []const u8,
full_name: ?[]const u8,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,
completed_timestamp_ms: ?i64,

// Attachments/Images
// Tags

pub const Index = enum (u32) { _ };

const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
