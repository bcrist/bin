arena: std.heap.ArenaAllocator,
container_alloc: std.mem.Allocator,

loading: bool = false,
dirty_timestamp_ms: ?i64 = null,
last_modification_timestamp_ms: ?i64 = null,

strings: std.StringHashMapUnmanaged(void) = .{},

mfr_lookup: std.StringHashMapUnmanaged(Manufacturer.Index) = .{},
mfrs: std.MultiArrayList(Manufacturer) = .{},
mfr_relations: std.MultiArrayList(Manufacturer.Relation) = .{},

const DB = @This();
pub const Manufacturer = @import("db/Manufacturer.zig");
pub const Distributor = @import("db/Distributor.zig");
pub const Part = @import("db/Part.zig");
pub const Order = @import("db/Order.zig");
pub const Project = @import("db/Project.zig");
pub const Package = @import("db/Package.zig");
pub const Location = @import("db/Location.zig");

pub fn deinit(self: *DB) void {
    const gpa = self.container_alloc;

    for (self.mfrs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }

    self.mfr_relations.deinit(gpa);
    self.mfrs.deinit(gpa);
    self.mfr_lookup.deinit(gpa);
    self.strings.deinit(gpa);
    self.arena.deinit();
    self.dirty_timestamp_ms = null;
    self.last_modification_timestamp_ms = null;
    self.loading = false;
}

pub fn reset(self: *DB) void {
    const gpa = self.container_alloc;

    for (self.mfrs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }

    self.mfrs.len = 0;
    self.mfr_relations.len = 0;
    self.mfr_lookup.clearRetainingCapacity();
    self.strings.clearRetainingCapacity();
    self.arena.reset(.retain_capacity);
    self.dirty_timestamp_ms = null;
    self.last_modification_timestamp_ms = null;
    self.loading = false;
}

/// This should only be necessary after importing with .loading = true;
/// otherwise mark_dirty() will keep it up-to-date.
pub fn recompute_last_modification_time(self: *DB) void {
    var last_mod: i64 = 0;
    for (self.mfrs.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    log.debug("Updated last modification time to {}", .{ last_mod });
    self.last_modification_timestamp_ms = last_mod;
}

pub const Import_Options = struct {
    loading: bool = false,
    prefix: []const u8 = "",
};

pub fn import_data(self: *DB, dir: *std.fs.Dir, options: Import_Options) !void {
    var temp_arena = try Temp_Allocator.init(500 * 1024 * 1024);
    defer temp_arena.deinit();
    
    var walker = try dir.walk(temp_arena.allocator());
    defer walker.deinit();

    self.loading = options.loading;

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!options.loading and std.mem.startsWith(u8, entry.basename, "_")) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".sx")) continue;

        const temp_snapshot = temp_arena.snapshot();
        defer temp_arena.release_to_snapshot(temp_snapshot);

        if (options.loading) {
            log.debug("Loading {s}", .{
                try std.fs.path.resolve(temp_arena.allocator(), &.{
                    options.prefix,
                    entry.path,
                }),
            });
        } else {
            log.info("Importing {s}", .{
                try std.fs.path.resolve(temp_arena.allocator(), &.{
                    options.prefix,
                    entry.path,
                }),
            });
        }

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
    if (self.loading) return;

    if (self.dirty_timestamp_ms) |dirty| {
        if (timestamp_ms < dirty) {
            log.debug("Updated dirty time to {}", .{ timestamp_ms });
            self.dirty_timestamp_ms = timestamp_ms;
        }
    } else {
        log.debug("Updated dirty time to {}", .{ timestamp_ms });
        self.dirty_timestamp_ms = timestamp_ms;
    }

    if (self.last_modification_timestamp_ms) |last| {
        if (timestamp_ms <= last) return;
    }
    log.debug("Updated last modification time to {}", .{ timestamp_ms });
    self.last_modification_timestamp_ms = timestamp_ms;
}

pub fn intern(self: *DB, str: []const u8) ![]const u8 {
    if (self.strings.getKey(str)) |interned| return interned;
    intern_log.debug("Interning string \"{}\"", .{ std.zig.fmtEscapes(str) });
    const duped = try self.arena.allocator().dupe(u8, str);
    try self.strings.put(self.container_alloc, duped, {});
    return duped;
}
pub fn maybe_intern(self: *DB, maybe_str: ?[]const u8) !?[]const u8 {
    return if (maybe_str) |str| try self.intern(str) else null;
}

const log = std.log.scoped(.db);
const intern_log = std.log.scoped(.db_intern);
    
const v1 = @import("db/v1.zig");

const Temp_Allocator = @import("Temp_Allocator");
const sx = @import("sx");
const std = @import("std");
