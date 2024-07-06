arena: std.heap.ArenaAllocator,
container_alloc: std.mem.Allocator,

loading: bool = false,
last_modification_timestamp_ms: ?i64 = null,
dirty_set: std.AutoArrayHashMapUnmanaged(Any_Index, void) = .{},

strings: std.StringHashMapUnmanaged(void) = .{},

mfr_lookup: maps.String_Hash_Map_Ignore_Case_Unmanaged(Manufacturer.Index) = .{},
mfrs: std.MultiArrayList(Manufacturer) = .{},
mfr_relations: std.MultiArrayList(Manufacturer.Relation) = .{},

dist_lookup: maps.String_Hash_Map_Ignore_Case_Unmanaged(Distributor.Index) = .{},
dists: std.MultiArrayList(Distributor) = .{},
dist_relations: std.MultiArrayList(Distributor.Relation) = .{},

loc_lookup: maps.String_Hash_Map_Ignore_Case_Unmanaged(Location.Index) = .{},
locs: std.MultiArrayList(Location) = .{},

pkg_lookup: maps.Qualified_String_Hash_Map_Ignore_Case_Unmanaged(?Manufacturer.Index, Package.Index) = .{},
pkgs: std.MultiArrayList(Package) = .{},

dist_part_lookup: maps.Qualified_String_Hash_Map_Ignore_Case_Unmanaged(Distributor.Index, Part.Index) = .{},
part_lookup: maps.Qualified_String_Hash_Map_Ignore_Case_Unmanaged(?Manufacturer.Index, Part.Index) = .{},
parts: std.MultiArrayList(Part) = .{},

prj_lookup: maps.String_Hash_Map_Ignore_Case_Unmanaged(Project.Index) = .{},
prjs: std.MultiArrayList(Project) = .{},

order_lookup: maps.String_Hash_Map_Ignore_Case_Unmanaged(Order.Index) = .{},
orders: std.MultiArrayList(Order) = .{},
//prj_order_links: std.AutoArrayHashMapUnmanaged(Order.Project_Link, void) = .{},
//order_items: std.MultiArrayList(Order_Item) = .{},

const DB = @This();
pub const Manufacturer = @import("db/Manufacturer.zig");
pub const Distributor = @import("db/Distributor.zig");
pub const Part = @import("db/Part.zig");
pub const Order = @import("db/Order.zig");
//pub const Order_Item = @import("db/Order_Item.zig");
pub const Project = @import("db/Project.zig");
pub const Package = @import("db/Package.zig");
pub const Location = @import("db/Location.zig");

pub const Any_Index = union (enum) {
    mfr: Manufacturer.Index,
    dist: Distributor.Index,
    part: Part.Index,
    order: Order.Index,
    prj: Project.Index,
    pkg: Package.Index,
    loc: Location.Index,

    pub fn init(index: anytype) Any_Index {
        return switch (@TypeOf(index).Type) {
            Any_Index => index,
            Manufacturer => .{ .mfr = index },
            Distributor => .{ .dist = index },
            Part => .{ .part = index },
            Order => .{ .order = index },
            Project => .{ .prj = index },
            Package => .{ .pkg = index },
            Location => .{ .loc = index },
            else => unreachable,
        };
    }

    pub fn name(self: Any_Index, db: *const DB, arena: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .mfr => |idx| Manufacturer.get_id(db, idx),
            .dist => |idx| Distributor.get_id(db, idx),
            .order => |idx| Order.get_id(db, idx),
            .prj => |idx| Project.get_id(db, idx),
            .loc => |idx| Location.get_id(db, idx),
            .part => |idx| {
                const id = Part.get_id(db, idx);
                if (Part.get_mfr(db, idx)) |mfr_idx| {
                    const mfr_id = DB.Manufacturer.get_id(db, mfr_idx);
                    return try std.fmt.allocPrint(arena, "{s} {s}", .{ mfr_id, id });
                }
                return id;
            },
            .pkg => |idx| {
                const id = Package.get_id(db, idx);
                if (Package.get_mfr(db, idx)) |mfr_idx| {
                    const mfr_id = DB.Manufacturer.get_id(db, mfr_idx);
                    return try std.fmt.allocPrint(arena, "{s} {s}", .{ mfr_id, id });
                }
                return id;
            },
        };
    }
};

pub fn deinit(self: *DB) void {
    const gpa = self.container_alloc;

    self.orders.deinit(gpa);
    self.order_lookup.deinit(gpa);

    self.prjs.deinit(gpa);
    self.prj_lookup.deinit(gpa);

    for (self.parts.items(.dist_pns)) |*list| {
        list.deinit(gpa);
    }
    self.parts.deinit(gpa);
    self.part_lookup.deinit(gpa);
    self.dist_part_lookup.deinit(gpa);

    for (self.pkgs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }
    self.pkgs.deinit(gpa);
    self.pkg_lookup.deinit(gpa);

    self.locs.deinit(gpa);
    self.loc_lookup.deinit(gpa);

    for (self.dists.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }
    self.dist_relations.deinit(gpa);
    self.dists.deinit(gpa);
    self.dist_lookup.deinit(gpa);

    for (self.mfrs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }
    self.mfr_relations.deinit(gpa);
    self.mfrs.deinit(gpa);
    self.mfr_lookup.deinit(gpa);

    self.strings.deinit(gpa);
    
    self.dirty_set.deinit(gpa);

    self.arena.deinit();
    self.last_modification_timestamp_ms = null;
    self.loading = false;
}

pub fn reset(self: *DB) void {
    const gpa = self.container_alloc;

    self.orders.len = 0;
    self.order_lookup.clearRetainingCapacity();

    self.prjs.len = 0;
    self.prj_lookup.clearRetainingCapacity();

    for (self.parts.items(.dist_pns)) |*list| {
        list.deinit(gpa);
    }
    self.parts.len = 0;
    self.part_lookup.clearRetainingCapacity();
    self.dist_part_lookup.clearRetainingCapacity();

    for (self.pkgs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }
    self.pkgs.len = 0;
    self.pkg_lookup.clearRetainingCapacity();

    self.locs.len = 0;
    self.loc_lookup.clearRetainingCapacity();

    for (self.dists.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }
    self.dists.len = 0;
    self.dist_relations.len = 0;
    self.dist_lookup.clearRetainingCapacity();

    for (self.mfrs.items(.additional_names)) |*list| {
        list.deinit(gpa);
    }
    self.mfrs.len = 0;
    self.mfr_relations.len = 0;
    self.mfr_lookup.clearRetainingCapacity();

    self.strings.clearRetainingCapacity();

    self.dirty_set.clearRetainingCapacity();

    self.arena.reset(.retain_capacity);
    self.last_modification_timestamp_ms = null;
    self.loading = false;
}

fn get_list(self: *const DB, comptime T: type) std.MultiArrayList(T) {
    return switch (T) {
        Manufacturer => self.mfrs,
        Distributor => self.dists,
        Part => self.parts,
        Order => self.orders,
        Project => self.prjs,
        Package => self.pkgs,
        Location => self.locs,
        else => unreachable,
    };
}

pub const Import_Options = struct {
    path: []const u8,
    loading: bool = false,
};

pub fn import_data(self: *DB, options: Import_Options) !void {
    var temp_arena = try Temp_Allocator.init(500 * 1024 * 1024);
    defer temp_arena.deinit();
    
    var dir = try std.fs.cwd().makeOpenPath(options.path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(temp_arena.allocator());
    defer walker.deinit();

    self.loading = options.loading;
    defer self.loading = false;

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!options.loading and std.mem.startsWith(u8, entry.basename, "_")) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".sx")) continue;

        const temp_snapshot = temp_arena.snapshot();
        defer temp_arena.release_to_snapshot(temp_snapshot);

        if (options.loading) {
            log.debug("Loading {s}", .{
                try std.fs.path.resolve(temp_arena.allocator(), &.{
                    if (options.loading) "" else options.path,
                    entry.path,
                }),
            });
        } else {
            log.info("Importing {s}", .{
                try std.fs.path.resolve(temp_arena.allocator(), &.{
                    if (options.loading) "" else options.path,
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
    if (self.dirty_set.count() == 0) return;
    try v1.write_data(self, dir);
    self.dirty_set.clearRetainingCapacity();
}

/// This should only be necessary after importing with .loading = true;
/// otherwise update_modification_time() will keep it up-to-date.
pub fn recompute_last_modification_time(self: *DB) void {
    var last_mod: i64 = 0;
    for (self.mfrs.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    for (self.dists.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    for (self.locs.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    for (self.pkgs.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    for (self.parts.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    for (self.prjs.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    for (self.orders.items(.modified_timestamp_ms)) |ts| {
        if (ts > last_mod) last_mod = ts;
    }
    log.debug("Updated last modification time to {}", .{ last_mod });
    self.last_modification_timestamp_ms = last_mod;
}

pub fn update_modification_time(self: *DB, timestamp_ms: i64) void {
    if (self.loading) return;

    if (self.last_modification_timestamp_ms) |last| {
        if (timestamp_ms <= last) return;
    }
    log.debug("Updated last modification time to {}", .{ timestamp_ms });
    self.last_modification_timestamp_ms = timestamp_ms;
}

pub fn mark_dirty(self: *DB, idx: anytype) !void {
    if (self.loading) return;

    const ai = Any_Index.init(idx);
    try self.dirty_set.put(self.container_alloc, ai, {});
}

pub fn maybe_set_modified(self: *DB, idx: anytype) !void {
    const Index = @TypeOf(idx);
    if (comptime @typeInfo(Index) == .Enum and @hasDecl(Index, "Type") and std.mem.endsWith(u8, @typeName(Index), ".Index")) {
        if (self.loading) return;
        const list = self.get_list(Index.Type);
        const i = idx.raw();
        const now = std.time.milliTimestamp();
        const DTO = tempora.Date_Time.With_Offset;
        const now_dto = DTO.from_timestamp_ms(now, null);
        log.debug("Setting {} last modified to " ++ DTO.sql_ms, .{ idx, now_dto });
        list.items(.modified_timestamp_ms)[i] = now;
        self.update_modification_time(now);
        try self.mark_dirty(idx);
    }
}

pub fn set_optional(self: *DB, comptime T: type, idx: T.Index, comptime field: @TypeOf(.enum_field), comptime F: type, raw: ?F) !void {
    const i = idx.raw();
    const list = self.get_list(T);
    const array = list.items(field);
    if (array[i]) |current| {
        if (raw) |new| {
            if (F == []const u8) {
                if (!std.mem.eql(u8, current, new)) {
                    array[i] = try self.intern(new);
                    try self.maybe_set_modified(idx);
                }
            } else {
                if (!std.meta.eql(current, new)) {
                    if (F == T.Index) {
                        if (array[i]) |old| {
                            try self.maybe_set_modified(old);
                        }
                        try self.maybe_set_modified(new);
                    }
                    array[i] = new;
                    try self.maybe_set_modified(idx);
                }
            }
            
        } else {
            // removing
            if (F == T.Index) {
                if (array[i]) |old| {
                    try self.maybe_set_modified(old);
                }
            }
            array[i] = null;
            try self.maybe_set_modified(idx);
        }
    } else {
        if (raw) |new| {
            // adding
            if (F == []const u8) {
                array[i] = try self.intern(new);
            } else {
                if (F == T.Index) {
                    try self.maybe_set_modified(new);
                }
                array[i] = new;
            }
            try self.maybe_set_modified(idx);
        }
    }
}

pub fn get_id(self: *const DB, idx: anytype) []const u8 {
    return self.get_list(@TypeOf(idx).Type).items(.id)[idx.raw()];
}

pub fn is_valid_id(id: []const u8) bool {
    if (id.len == 0) return false;
    if (std.mem.eql(u8, id, "_")) return false;
    if (std.mem.trim(u8, id, &std.ascii.whitespace).len < id.len) return false;
    return true;
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
const intern_log = std.log.scoped(.@"db.intern");
    
const v1 = @import("db/v1.zig");

const maps = @import("maps.zig");
const Temp_Allocator = @import("Temp_Allocator");
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
