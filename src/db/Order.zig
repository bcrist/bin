
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

const Order = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Order;
    
    pub inline fn init(i: usize) Index {
        const raw_i: u32 = @intCast(i);
        return @enumFromInt(raw_i);
    }

    pub inline fn any(self: Index) DB.Any_Index {
        return DB.Any_Index.init(self);
    }

    pub inline fn raw(self: Index) u32 {
        return @intFromEnum(self);
    }
};

const DB = @import("../DB.zig");
const Date_Time = @import("tempora").Date_Time;
const std = @import("std");
