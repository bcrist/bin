
id: []const u8,
full_name: ?[]const u8,
parent: ?Index,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,

// ancestors
// children
// descendents
// dimensions (rows/columns)
// inventories
// Attachments/Images
// Tags - lead free

const Location = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Location;
};

pub fn init_empty(id: []const u8, timestamp_ms: i64) Location {
    return .{
        .id = id,
        .full_name = null,
        .parent = null,
        .notes = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
    };
}

pub fn maybe_lookup(db: *const DB, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.loc_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_multiple(db: *const DB, possible_names: []const []const u8) ?Index {
    for (possible_names) |name| {
        if (db.loc_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, id: []const u8) !Index {
    if (db.loc_lookup.get(id)) |idx| return idx;
    
    const idx: Index = @enumFromInt(db.locs.len);
    const now = std.time.milliTimestamp();
    const loc = init_empty(try db.intern(id), now);
    try db.locs.append(db.container_alloc, loc);
    try db.loc_lookup.putNoClobber(db.container_alloc, loc.id, idx);
    db.mark_dirty(now);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Location {
    return db.locs.get(@intFromEnum(idx));
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.locs.items(.id)[@intFromEnum(idx)];
}

pub inline fn get_full_name(db: *const DB, idx: Index) ?[]const u8 {
    return db.locs.items(.full_name)[@intFromEnum(idx)];
}

pub inline fn get_parent(db: *const DB, idx: Index) ?Index {
    return db.locs.items(.parent)[@intFromEnum(idx)];
}

pub fn is_ancestor(db: *const DB, descendant_idx: Index, ancestor_idx: Index) bool {
    const parents = db.locs.items(.parent);
    var maybe_idx: ?Index = descendant_idx;
    var depth: usize = 0;
    while (maybe_idx) |idx| {
        if (idx == ancestor_idx) return true;

        const i = @intFromEnum(idx);
        if (depth > 1000) {
            log.warn("Too many location ancestors; probably recursive parent chain involving {s}", .{
                db.locs.items(.id)[i],
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

    const parents = db.locs.items(.parent);
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

    std.debug.assert(db.loc_lookup.remove(db.locs.items(.id)[i]));

    if (db.locs.items(.full_name)[i]) |full_name| {
        std.debug.assert(db.loc_lookup.remove(full_name));
    }

    if (parents[@intFromEnum(idx)]) |parent_idx| {
        set_modified(db, parent_idx);
    }

    const now = std.time.milliTimestamp();
    db.locs.set(i, init_empty("", now));
    db.mark_dirty(now);
}

pub fn set_id(db: *DB, idx: Index, id: []const u8) !void {
    const i = @intFromEnum(idx);
    const ids = db.locs.items(.id);
    const old_id = ids[i];
    if (std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.loc_lookup.remove(old_id));
    try db.loc_lookup.putNoClobber(db.container_alloc, new_id, idx);
    ids[i] = new_id;
    set_modified(db, idx);
}

pub fn set_full_name(db: *DB, idx: Index, full_name: ?[]const u8) !void {
    const i = @intFromEnum(idx);
    const full_names = db.locs.items(.full_name);
    const old_name = full_names[i];
    try set_optional([]const u8, db, idx, .full_name, full_name);
    const new_name = full_names[i];
    if (deep.deepEql(old_name, new_name, .Deep)) return;

    if (old_name) |name| {
        std.debug.assert(db.loc_lookup.remove(name));
    }
    if (new_name) |name| {
        try db.loc_lookup.putNoClobber(db.container_alloc, name, idx);
    }
}

pub fn set_parent(db: *DB, idx: Index, parent_idx: ?Index) !void {
    return set_optional(Index, db, idx, .parent, parent_idx);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const created_timestamps = db.locs.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const modified_timestamps = db.locs.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    db.mark_dirty(timestamp_ms);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Location, idx, field, T, raw);
}

fn set_modified(db: *DB, idx: Index) void {
    db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
