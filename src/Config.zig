db: []const u8 = "./db",
import: ?[]const u8 = null,
host: []const u8 = "0.0.0.0",
port: u16 = 16777,
http_threads: ?u32 = 10,
timezone: ?[]const u8 = null,

const Config = @This();

pub const context = struct {};

fn get_config_filename(buf: []u8) ![]const u8 {
    const filename = "zin.conf";
    const base_path = try std.fs.selfExeDirPath(buf);
    var remaining = buf[base_path.len..];

    const sep = std.fs.path.sep_str;
    if (!std.mem.endsWith(u8, base_path, sep)) {
        if (remaining.len < sep.len) {
            return error.NameTooLong;
        }
        @memcpy(remaining.ptr, sep);
        remaining = remaining[sep.len..];
    }

    if (remaining.len < filename.len) {
        return error.NameTooLong;
    }

    @memcpy(remaining.ptr, filename);
    remaining = remaining[filename.len..];

    return buf[0 .. buf.len - remaining.len];
}

pub fn load(arena: std.mem.Allocator) !Config {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try get_config_filename(&buf);
    
    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const default: Config = .{};
            try default.save();
            return default;
        },
        else => return err,
    };
    defer file.close();

    var temp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer temp_arena.deinit();

    var reader = sx.reader(temp_arena.allocator(), file.reader().any());
    defer reader.deinit();

    const config = reader.require_object(arena, Config, context) catch |err| switch (err) {
        error.SExpressionSyntaxError => {
            const ctx = try reader.token_context();
            try ctx.print_for_file(&file, std.io.getStdErr().writer(), 160);
            std.os.exit(1);
        },
        else => return err,
    };

    try reader.require_done();

    return config;
}

pub fn save(self: Config) !void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try get_config_filename(&buf);
    
    var af = try std.fs.cwd().atomicFile(path, .{});
    defer af.deinit();

    var temp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer temp_arena.deinit();

    var writer = sx.writer(temp_arena.allocator(), af.file.writer().any());
    defer writer.deinit();

    try writer.object(self, context);

    try af.finish();
}

const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
