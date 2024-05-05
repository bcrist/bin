arena: std.heap.ArenaAllocator,
container_alloc: std.mem.Allocator,

dirty_timestamp_ms: ?i64 = null,
last_modification_timestamp_ms: ?i64 = null,

strings: std.StringHashMapUnmanaged(void) = .{},

mfr_lookup: std.StringArrayHashMapUnmanaged(Manufacturer.Index) = .{},
mfrs: std.MultiArrayList(Manufacturer) = .{},



const DB = @This();

pub fn deinit(self: *DB) void {
    const gpa = self.container_alloc;

    for (self.mfrs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }

    self.mfrs.deinit(gpa);
    self.mfr_lookup.deinit(gpa);
    self.strings.deinit(gpa);
    self.arena.deinit();
    self.dirty_timestamp_ms = null;
    self.last_modification_timestamp_ms = null;
}

pub fn reset(self: *DB) void {

    for (self.mfrs.items(.additional_names)) |*list| {
        list.deinit(self.container_alloc);
    }

    self.mfrs.len = 0;
    self.mfr_lookup.clearRetainingCapacity();
    self.strings.clearRetainingCapacity();
    self.arena.reset(.retain_capacity);
    self.dirty_timestamp_ms = null;
    self.last_modification_timestamp_ms = null;
}

pub const Import_Options = struct {
    skip_underscores: bool = false,
    action: []const u8 = "Loading",
    prefix: []const u8 = "",
};

pub fn import_data(self: *DB, dir: *std.fs.Dir, options: Import_Options) !void {
    var temp_arena = try Temp_Allocator.init(500 * 1024 * 1024);
    defer temp_arena.deinit();
    
    var walker = try dir.walk(temp_arena.allocator());
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (options.skip_underscores and std.mem.startsWith(u8, entry.basename, "_")) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".sx")) continue;

        const temp_snapshot = temp_arena.snapshot();
        defer temp_arena.release_to_snapshot(temp_snapshot);

        log.info("{s} {s}", .{
            options.action,
            try std.fs.path.resolve(temp_arena.allocator(), &.{
                options.prefix,
                entry.path,
            }),
        });

        var file = try dir.openFile(entry.path, .{});
        defer file.close();

        var reader = sx.reader(temp_arena.allocator(), file.reader().any());
        defer reader.deinit();

        self.parse_data(&reader) catch |err| switch (err) {
            error.SExpressionSyntaxError => {
                const ctx = try reader.token_context();
                try ctx.print_for_file(&file, std.io.getStdErr().writer(), 160);
            },
            else => return err,
        };
    }
}

fn parse_data(self: *DB, reader: *sx.Reader) !void {
    try reader.require_expression("version");
    const version = try reader.require_any_int(u64, 10);
    try reader.require_close();
    switch (version) {
        1 => {
            try v1.parse_data(self, reader);
        },
        else => {
            try std.io.getStdErr().writer().print("Unsupported data version: {}\n", .{ version });
            return error.SExpressionSyntaxError;
        },
    }
    try reader.require_done();
}

pub fn export_data(self: *DB, dir: *std.fs.Dir) !void {
    try v1.write_data(self, dir);
}

pub fn mark_dirty(self: *DB, timestamp_ms: i64) void {
    if (self.dirty_timestamp_ms) |dirty| {
        if (timestamp_ms < dirty) {
            self.dirty_timestamp_ms = timestamp_ms;
        }
    } else {
        self.dirty_timestamp_ms = timestamp_ms;
    }

    if (self.last_modification_timestamp_ms) |last| {
        if (timestamp_ms > last) {
            self.last_modification_timestamp_ms = timestamp_ms;
        }
    } else {
        self.last_modification_timestamp_ms = timestamp_ms;
    }
}

pub fn intern(self: *DB, str: []const u8) ![]const u8 {
    if (self.strings.getKey(str)) |interned| return interned;
    const duped = try self.arena.allocator().dupe(u8, str);
    try self.strings.put(self.container_alloc, duped, {});
    return duped;
}
pub fn maybe_intern(self: *DB, maybe_str: ?[]const u8) !?[]const u8 {
    return if (maybe_str) |str| try self.intern(str) else null;
}



const log = std.log.scoped(.db);
    
const Manufacturer = @import("db/Manufacturer.zig");
const Distributor = @import("db/Distributor.zig");
const Part = @import("db/Part.zig");
const Order = @import("db/Order.zig");
const Project = @import("db/Project.zig");
const Package = @import("db/Package.zig");
const Location = @import("db/Location.zig");

const v1 = @import("db/v1.zig");

const Temp_Allocator = @import("Temp_Allocator");
const sx = @import("sx");
const std = @import("std");
