pub fn get(req: *http.Request) !void {
    log.info("Headers:", .{});
    var iter = req.header_iterator();
    while (iter.next()) |header| {
        log.info("  {s}: {s}", .{ header.name, header.value });
    }

    log.info("Body:", .{});
    var line_buffer = try std.ArrayList(u8).initCapacity(http.temp(), 120);
    var reader = try req.req.reader();
    while (true) {
        line_buffer.clearRetainingCapacity();
        reader.streamUntilDelimiter(line_buffer.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => {
                if (line_buffer.getLastOrNull()) |last| {
                    if (last == '\r') line_buffer.items.len -= 1;
                }
                log.info("{s}", .{ line_buffer.items });
                break;
            },
            else => return err,
        };
        if (line_buffer.getLastOrNull()) |last| {
            if (last == '\r') line_buffer.items.len -= 1;
        }
        log.info("  {s}", .{ line_buffer.items });
    }
}

pub const post = get;
pub const put = get;
pub const delete = get;
pub const connect = get;
pub const options = get;
pub const trace = get;
pub const patch = get;

const log = std.log.scoped(.http_debug);

const http = @import("http");
const std = @import("std");
