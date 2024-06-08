
id: []const u8,
full_name: []const u8,
country: []const u8,
website: []const u8,
wiki: []const u8,
notes: []const u8,
created: Date_Time,
modified: Date_Time,

// Alternative names
// Related distributors
// Attachments/Images
// orders tagged with this distributor

const Distributor = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Distributor;
};

const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
