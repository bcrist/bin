id: []const u8,
full_name: []const u8,
country: ?[]const u8,
website: ?[]const u8,
wiki: ?[]const u8,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,

// Alternative names
// Related mfrs
// Attachments/Images
// Parts tagged with this mfr

pub const Index = enum (u32) { _ };


const std = @import("std");
