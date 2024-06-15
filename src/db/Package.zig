
id: []const u8,
full_name: ?[]const u8,
parent: ?Index,
mfr: ?Manufacturer.Index,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,
additional_names: std.ArrayListUnmanaged([]const u8),

// ancestors
// children
// descendents
// parts using pkg
// Attachments/Images/Datasheets/3D models/footprints
// Parameters - pin count, pin pitch, bounding dimensions, body dimensions
// Parameters expected for children
// Tags - lead free

const Package = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Package;
};

pub fn init_empty(id: []const u8, timestamp_ms: i64) Package {
    return .{
        .id = id,
        .full_name = null,
        .parent = null,
        .mfr = null,
        .notes = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
        .additional_names = .{},
    };
}

pub fn maybe_lookup(db: *const DB, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.pkg_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_multiple(db: *const DB, possible_names: []const []const u8) ?Index {
    for (possible_names) |name| {
        if (db.pkg_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, id: []const u8) !Index {
    if (db.pkg_lookup.get(id)) |idx| return idx;
    
    const idx: Index = @enumFromInt(db.pkgs.len);
    const now = std.time.milliTimestamp();
    const pkg = init_empty(try db.intern(id), now);
    try db.pkgs.append(db.container_alloc, pkg);
    try db.pkg_lookup.putNoClobber(db.container_alloc, pkg.id, idx);
    db.mark_dirty(now);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Package {
    return db.pkgs.get(@intFromEnum(idx));
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.pkgs.items(.id)[@intFromEnum(idx)];
}

pub inline fn get_full_name(db: *const DB, idx: Index) ?[]const u8 {
    return db.pkgs.items(.full_name)[@intFromEnum(idx)];
}

pub inline fn get_parent(db: *const DB, idx: Index) ?Index {
    return db.pkgs.items(.parent)[@intFromEnum(idx)];
}

pub inline fn get_additional_names(db: *const DB, idx: Index) []const []const u8 {
    return db.pkgs.items(.additional_names)[@intFromEnum(idx)].items;
}

pub inline fn get_mfr(db: *const DB, idx: Index) ?Manufacturer.Index {
    return db.pkgs.items(.mfr)[@intFromEnum(idx)];
}

pub fn is_ancestor(db: *const DB, descendant_idx: Index, ancestor_idx: Index) bool {
    const parents = db.pkgs.items(.parent);
    var maybe_idx: ?Index = descendant_idx;
    var depth: usize = 0;
    while (maybe_idx) |idx| {
        if (idx == ancestor_idx) return true;

        const i = @intFromEnum(idx);
        if (depth > 1000) {
            log.warn("Too many package ancestors; probably recursive parent chain involving {s}", .{
                db.pkgs.items(.id)[i],
            });
            return false;
        } else {
            depth += 1;
            maybe_idx = parents[i];
        }
    }
    return false;
}

pub fn delete(db: *DB, idx: Index, recursive: bool) !void {
    const i = @intFromEnum(idx);

    const parents = db.pkgs.items(.parent);
    for (0.., parents) |child_idx, maybe_parent_idx| {
        if (maybe_parent_idx) |parent_idx| {
            if (parent_idx == idx) {
                if (recursive) {
                    try delete(db, @enumFromInt(child_idx), true);
                } else {
                    try set_parent(db, @enumFromInt(child_idx), null);
                }
            }
        }
    }

    std.debug.assert(db.pkg_lookup.remove(db.pkgs.items(.id)[i]));

    if (db.pkgs.items(.full_name)[i]) |full_name| {
        std.debug.assert(db.pkg_lookup.remove(full_name));
    }

    const additional_names: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    for (additional_names.items) |name| {
        std.debug.assert(db.pkg_lookup.remove(name));
    }
    additional_names.deinit(db.container_alloc);

    if (parents[@intFromEnum(idx)]) |parent_idx| {
        set_modified(db, parent_idx);
    }

    const now = std.time.milliTimestamp();
    db.pkgs.set(i, init_empty("", now));
    db.mark_dirty(now);
}

pub fn set_id(db: *DB, idx: Index, id: []const u8) !void {
    const i = @intFromEnum(idx);
    const ids = db.pkgs.items(.id);
    const old_id = ids[i];
    if (std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.pkg_lookup.remove(old_id));
    try db.pkg_lookup.putNoClobber(db.container_alloc, new_id, idx);
    ids[i] = new_id;
    set_modified(db, idx);
}

pub fn set_full_name(db: *DB, idx: Index, full_name: ?[]const u8) !void {
    const i = @intFromEnum(idx);
    const full_names = db.pkgs.items(.full_name);
    const old_name = full_names[i];
    try set_optional([]const u8, db, idx, .full_name, full_name);
    const new_name = full_names[i];
    if (deep.deepEql(old_name, new_name, .Deep)) return;

    if (old_name) |name| {
        std.debug.assert(db.pkg_lookup.remove(name));
    }
    if (new_name) |name| {
        try db.pkg_lookup.putNoClobber(db.container_alloc, name, idx);
    }
}

pub fn set_parent(db: *DB, idx: Index, parent_idx: ?Index) !void {
    return set_optional(Index, db, idx, .parent, parent_idx);
}

pub fn set_mfr(db: *DB, idx: Index, mfr_idx: ?Manufacturer.Index) !void {
    return set_optional(Manufacturer.Index, db, idx, .mfr, mfr_idx);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const created_timestamps = db.pkgs.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const modified_timestamps = db.pkgs.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    db.mark_dirty(timestamp_ms);
}

pub fn add_additional_names(db: *DB, idx: Index, additional_names: []const []const u8) !void {
    if (additional_names.len == 0) return;

    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    try list.ensureUnusedCapacity(db.container_alloc, additional_names.len);

    var added_name = false;

    for (additional_names) |raw_name| {
        const gop = try db.pkg_lookup.getOrPut(db.container_alloc, raw_name);
        if (gop.found_existing) {
            if (idx != gop.value_ptr.*) {
                const ids = db.pkgs.items(.id);
                log.err("Ignoring additional name \"{}\" for package \"{}\" because it is already associated with \"{}\"", .{
                    std.zig.fmtEscapes(raw_name),
                    std.zig.fmtEscapes(ids[@intFromEnum(idx)]),
                    std.zig.fmtEscapes(ids[@intFromEnum(gop.value_ptr.*)]),
                });
            }
        } else {
            const name = try db.intern(raw_name);
            gop.key_ptr.* = name;
            gop.value_ptr.* = idx;
            list.appendAssumeCapacity(name);
            added_name = true;
        }
    }

    if (added_name) {
        set_modified(db, idx);
    }
}

pub fn remove_additional_name(db: *DB, idx: Index, additional_name: []const u8) !void {
    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    
    for (0.., list.items) |list_index, name| {
        if (std.mem.eql(u8, name, additional_name)) {
            std.debug.assert(db.pkg_lookup.remove(name));
            _ = list.orderedRemove(list_index);
            break;
        }
    } else return;

    set_modified(db, idx);
}

pub fn rename_additional_name(db: *DB, idx: Index, old_name: []const u8, new_name: []const u8) !void {
    if (std.mem.eql(u8, old_name, new_name)) return;

    const interned = try db.intern(new_name);
    try db.pkg_lookup.putNoClobber(db.container_alloc, interned, idx);

    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    
    for (0.., list.items) |list_index, name| {
        if (std.mem.eql(u8, name, old_name)) {
            std.debug.assert(db.pkg_lookup.remove(old_name));
            list.items[list_index] = interned;
            break;
        }
    } else {
        try list.append(db.container_alloc, interned);
    }

    set_modified(db, idx);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Package, idx, field, T, raw);
}

inline fn set_modified(db: *DB, idx: Index) void {
    db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const Manufacturer = @import("Manufacturer.zig");
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
