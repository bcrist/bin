id: []const u8,
full_name: ?[]const u8,
parent: ?Index,
status: Status,
status_change_timestamp_ms: i64,
notes: ?[]const u8,
website: ?[]const u8,
source_control: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,

// Attachments/Images
// Steps

pub const Status = enum {
    active,
    on_hold,
    abandoned,
    completed,

    pub fn display(self: Status) []const u8 {
        return switch (self) {
            .active => "Active",
            .on_hold => "On Hold",
            .abandoned => "Abandoned",
            .completed => "Completed",
        };
    }
};

const Project = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Project;
    
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

pub fn init_empty(id: []const u8, timestamp_ms: i64) Project {
    return .{
        .id = id,
        .full_name = null,
        .parent = null,
        .status = .active,
        .status_change_timestamp_ms = timestamp_ms,
        .notes = null,
        .website = null,
        .source_control = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
    };
}

pub fn maybe_lookup(db: *const DB, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.prj_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_multiple(db: *const DB, possible_names: []const []const u8) ?Index {
    for (possible_names) |name| {
        if (db.prj_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, id: []const u8) !Index {
    if (db.prj_lookup.get(id)) |idx| return idx;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;
    
    const idx = Index.init(db.prjs.len);
    const now = std.time.milliTimestamp();
    const prj = init_empty(try db.intern(id), now);
    try db.prjs.append(db.container_alloc, prj);
    try db.prj_lookup.putNoClobber(db.container_alloc, prj.id, idx);
    try db.mark_dirty(idx);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Project {
    return db.prjs.get(idx.raw());
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.prjs.items(.id)[idx.raw()];
}

pub inline fn get_full_name(db: *const DB, idx: Index) ?[]const u8 {
    return db.prjs.items(.full_name)[idx.raw()];
}

pub inline fn get_parent(db: *const DB, idx: Index) ?Index {
    return db.prjs.items(.parent)[idx.raw()];
}

pub fn is_ancestor(db: *const DB, descendant_idx: Index, ancestor_idx: Index) bool {
    const parents = db.prjs.items(.parent);
    var maybe_idx: ?Index = descendant_idx;
    var depth: usize = 0;
    while (maybe_idx) |idx| {
        if (idx == ancestor_idx) return true;

        const i = idx.raw();
        if (depth > 1000) {
            log.warn("Too many project ancestors; probably recursive parent chain involving {s}", .{
                db.prjs.items(.id)[i],
            });
            return false;
        } else {
            depth += 1;
            maybe_idx = parents[i];
        }
    }
    return false;
}

pub inline fn get_status(db: *const DB, idx: Index) Status {
    return db.prjs.items(.status)[idx.raw()];
}

pub fn delete(db: *DB, idx: Index, recursive: bool) !void {
    // TODO remove project link from any orders referencing this

    const i = idx.raw();

    const parents = db.prjs.items(.parent);
    const maybe_parent_idx = parents[i];
    for (0.., parents) |child_i, maybe_child_parent_idx| {
        if (maybe_child_parent_idx) |parent_idx| {
            if (parent_idx == idx) {
                if (recursive) {
                    try delete(db, Index.init(child_i), true);
                } else {
                    try set_parent(db, Index.init(child_i), maybe_parent_idx);
                }
            }
        }
    }

    std.debug.assert(db.prj_lookup.remove(db.prjs.items(.id)[i]));

    if (db.prjs.items(.full_name)[i]) |full_name| {
        std.debug.assert(db.prj_lookup.remove(full_name));
    }

    if (maybe_parent_idx) |parent_idx| {
        try db.mark_dirty(parent_idx);
    }

    db.prjs.set(i, init_empty("", std.time.milliTimestamp()));
    try db.mark_dirty(idx);
}

pub fn set_id(db: *DB, idx: Index, id: []const u8) !void {
    const i = idx.raw();
    const ids = db.prjs.items(.id);
    const old_id = ids[i];
    if (std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.prj_lookup.remove(old_id));
    try db.prj_lookup.putNoClobber(db.container_alloc, new_id, idx);
    ids[i] = new_id;
    try set_modified(db, idx);

    if (db.loading) return;

    for (0.., db.prjs.items(.parent)) |child_i, maybe_parent_idx| {
        if (maybe_parent_idx) |parent_idx| {
            if (parent_idx == idx) {
                try db.mark_dirty(Index.init(child_i));
            }
        }
    }

    // TODO mark dirty any orders referencing this project
}

pub fn set_full_name(db: *DB, idx: Index, full_name: ?[]const u8) !void {
    const i = idx.raw();
    const full_names = db.prjs.items(.full_name);
    const old_name = full_names[i];
    try set_optional([]const u8, db, idx, .full_name, full_name);
    const new_name = full_names[i];
    if (deep.deepEql(old_name, new_name, .Deep)) return;

    if (old_name) |name| {
        std.debug.assert(db.prj_lookup.remove(name));
    }
    if (new_name) |name| {
        try db.prj_lookup.putNoClobber(db.container_alloc, name, idx);
    }
}

pub fn set_parent(db: *DB, idx: Index, parent_idx: ?Index) !void {
    return set_optional(Index, db, idx, .parent, parent_idx);
}

pub fn set_status(db: *DB, idx: Index, status: Status) !void {
    const i = idx.raw();
    const statuses = db.prjs.items(.status);
    if (status == statuses[i]) return;
    statuses[i] = status;
    try set_status_change_time(db, idx, std.time.milliTimestamp());
}

pub fn set_status_change_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const timestamps = db.prjs.items(.status_change_timestamp_ms);
    if (timestamp_ms == timestamps[i]) return;
    timestamps[i] = timestamp_ms;
    try set_modified(db, idx);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_website(db: *DB, idx: Index, url: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .website, url);
}

pub fn set_source_control(db: *DB, idx: Index, url: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .source_control, url);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const created_timestamps = db.prjs.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    try set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const modified_timestamps = db.prjs.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    try db.mark_dirty(idx);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Project, idx, field, T, raw);
}

fn set_modified(db: *DB, idx: Index) !void {
    try db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
