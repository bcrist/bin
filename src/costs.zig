pub fn hundreths_to_decimal(allocator: std.mem.Allocator, cost_hundreths: i32) ![]const u8 {
    const cost_int = @divTrunc(cost_hundreths, 100);
    const cost_cents = @abs(@mod(cost_hundreths, 100));
    return try std.fmt.allocPrint(allocator, "{d}.{d:0>2}", .{ cost_int, cost_cents });
}

pub fn decimal_to_hundreths(decimal_str: []const u8) !i32 {
    if (std.mem.indexOfScalar(u8, decimal_str, '.')) |decimal_pos| {
        const int: i32 = try std.fmt.parseInt(i25, decimal_str[0..decimal_pos], 10);
        const cents: i32 = try std.fmt.parseInt(u8, decimal_str[decimal_pos + 1 ..], 10);
        return int * 100 + if (int < 0) -cents else cents;
    }
    return 100 * try std.fmt.parseInt(i25, decimal_str, 10);
}


const std = @import("std");
