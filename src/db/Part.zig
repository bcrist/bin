
id: []const u8,
full_name: ?[]const u8,
parent: ?Index,
mfr: ?Manufacturer.Index,
pkg: ?Package.Index,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,
dist_pns: std.ArrayListUnmanaged(Distributor_Part_Number),

// ancestors
// children
// descendents
// inventories
// Attachments/Images/Datasheets/3D models/footprints
// Parameters - pin count, pin pitch, bounding dimensions, body dimensions
// Parameters expected for children
// Tags - lead free

const Part = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Part;
};

pub const Distributor_Part_Number = struct {
    dist: Distributor.Index,
    pn: []const u8,

    pub fn eql(self: Distributor_Part_Number, other: Distributor_Part_Number) bool {
        return self.dist == other.dist and std.mem.eql(u8, self.pn, other.pn);
    }
};

pub fn init_empty(id: []const u8, timestamp_ms: i64) Part {
    return .{
        .id = id,
        .full_name = null,
        .parent = null,
        .mfr = null,
        .pkg = null,
        .notes = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
        .dist_pns = .{},
    };
}

pub fn maybe_lookup(db: *const DB, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.part_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_multiple(db: *const DB, possible_names: []const []const u8) ?Index {
    for (possible_names) |name| {
        if (db.part_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, id: []const u8) !Index {
    if (db.part_lookup.get(id)) |idx| return idx;
    
    const idx: Index = @enumFromInt(db.parts.len);
    const now = std.time.milliTimestamp();
    const part = init_empty(try db.intern(id), now);
    try db.parts.append(db.container_alloc, part);
    try db.part_lookup.putNoClobber(db.container_alloc, part.id, idx);
    db.mark_dirty(now);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Part {
    return db.parts.get(@intFromEnum(idx));
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.parts.items(.id)[@intFromEnum(idx)];
}

pub inline fn get_full_name(db: *const DB, idx: Index) ?[]const u8 {
    return db.parts.items(.full_name)[@intFromEnum(idx)];
}

pub inline fn get_parent(db: *const DB, idx: Index) ?Index {
    return db.parts.items(.parent)[@intFromEnum(idx)];
}

pub inline fn get_dist_pns(db: *const DB, idx: Index) []const Distributor_Part_Number {
    return db.parts.items(.dist_pns)[@intFromEnum(idx)];
}

pub inline fn get_mfr(db: *const DB, idx: Index) ?Manufacturer.Index {
    return db.parts.items(.mfr)[@intFromEnum(idx)];
}

pub inline fn get_pkg(db: *const DB, idx: Index) ?Package.Index {
    return db.parts.items(.pkg)[@intFromEnum(idx)];
}

pub fn is_ancestor(db: *const DB, descendant_idx: Index, ancestor_idx: Index) bool {
    const parents = db.parts.items(.parent);
    var maybe_idx: ?Index = descendant_idx;
    var depth: usize = 0;
    while (maybe_idx) |idx| {
        if (idx == ancestor_idx) return true;

        const i = @intFromEnum(idx);
        if (depth > 1000) {
            log.warn("Too many part ancestors; probably recursive parent chain involving {s}", .{
                db.parts.items(.id)[i],
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

    const parents = db.parts.items(.parent);
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

    std.debug.assert(db.part_lookup.remove(db.parts.items(.id)[i]));

    if (db.parts.items(.full_name)[i]) |full_name| {
        std.debug.assert(db.part_lookup.remove(full_name));
    }

    db.parts.items(.dist_pns)[i].deinit(db.container_alloc);

    if (parents[@intFromEnum(idx)]) |parent_idx| {
        set_modified(db, parent_idx);
    }

    const now = std.time.milliTimestamp();
    db.parts.set(i, init_empty("", now));
    db.mark_dirty(now);
}

pub fn set_id(db: *DB, idx: Index, id: []const u8) !void {
    const i = @intFromEnum(idx);
    const ids = db.parts.items(.id);
    const old_id = ids[i];
    if (std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.part_lookup.remove(old_id));
    try db.part_lookup.putNoClobber(db.container_alloc, new_id, idx);
    ids[i] = new_id;
    set_modified(db, idx);
}

pub fn set_full_name(db: *DB, idx: Index, full_name: ?[]const u8) !void {
    const i = @intFromEnum(idx);
    const full_names = db.parts.items(.full_name);
    const old_name = full_names[i];
    try set_optional([]const u8, db, idx, .full_name, full_name);
    const new_name = full_names[i];
    if (deep.deepEql(old_name, new_name, .Deep)) return;

    if (old_name) |name| {
        std.debug.assert(db.part_lookup.remove(name));
    }
    if (new_name) |name| {
        try db.part_lookup.putNoClobber(db.container_alloc, name, idx);
    }
}

pub fn set_parent(db: *DB, idx: Index, parent_idx: ?Index) !void {
    return set_optional(Index, db, idx, .parent, parent_idx);
}

pub fn set_mfr(db: *DB, idx: Index, mfr_idx: ?Manufacturer.Index) !void {
    return set_optional(Manufacturer.Index, db, idx, .mfr, mfr_idx);
}

pub fn set_pkg(db: *DB, idx: Index, pkg_idx: ?Package.Index) !void {
    return set_optional(Package.Index, db, idx, .pkg, pkg_idx);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const created_timestamps = db.parts.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const modified_timestamps = db.parts.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    db.mark_dirty(timestamp_ms);
}

pub fn add_dist_pn(db: *DB, idx: Index, pn: Distributor_Part_Number) !void {
    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged(Distributor_Part_Number) = &db.parts.items(.dist_pns)[i];

    for (list.items) |existing_pn| {
        if (existing_pn.eql(pn)) return;
    }

    try list.append(db.container_alloc, .{
        .dist = pn.dist,
        .pn = try db.intern(pn.pn),
    });

    set_modified(db, idx);
}

pub fn remove_dist_pn(db: *DB, idx: Index, pn: Distributor_Part_Number) !void {
    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged(Distributor_Part_Number) = &db.parts.items(.dist_pns)[i];
    
    for (0.., list.items) |list_index, existing_pn| {
        if (existing_pn.eql(pn)) {
            _ = list.orderedRemove(list_index);
            break;
        }
    } else return;

    set_modified(db, idx);
}

pub fn edit_dist_pn(db: *DB, idx: Index, old: Distributor_Part_Number, new: Distributor_Part_Number) !void {
    if (old.eql(new)) return;

    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged(Distributor_Part_Number) = &db.parts.items(.dist_pns)[i];
    
    for (0.., list.items) |list_index, existing_pn| {
        if (existing_pn.eql(old)) {
            list.items[list_index] = new;
            break;
        }
    } else return;

    set_modified(db, idx);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Part, idx, field, T, raw);
}

fn set_modified(db: *DB, idx: Index) void {
    db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
