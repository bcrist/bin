
mfr: ?Manufacturer.Index,
id: []const u8,
parent: ?Index,
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

pub const Distributor_Part_Number = struct {
    dist: Distributor.Index,
    pn: []const u8,

    pub fn eql(self: Distributor_Part_Number, other: Distributor_Part_Number) bool {
        return self.dist == other.dist and std.mem.eql(u8, self.pn, other.pn);
    }
};

pub fn init_empty(mfr: ?Manufacturer.Index, id: []const u8, timestamp_ms: i64) Part {
    return .{
        .mfr = mfr,
        .id = id,
        .parent = null,
        .pkg = null,
        .notes = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
        .dist_pns = .{},
    };
}

pub fn maybe_lookup(db: *const DB, mfr: ?Manufacturer.Index, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.part_lookup.get(.{ mfr, name })) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, mfr: ?Manufacturer.Index, id: []const u8) !Index {
    if (db.part_lookup.get(.{ mfr, id })) |idx| return idx;
    
    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const idx = Index.init(db.parts.len);
    const now = std.time.milliTimestamp();
    const part = init_empty(mfr, try db.intern(id), now);
    try db.parts.append(db.container_alloc, part);
    try db.part_lookup.putNoClobber(db.container_alloc, .{ mfr, part.id }, idx);
    try db.mark_dirty(idx);
    return idx;
}

pub fn lookup_dist_pn(db: *const DB, dist: Distributor.Index, pn: []const u8) ?Index {
    return db.dist_part_lookup.get(.{ dist, pn });
}

pub inline fn get(db: *const DB, idx: Index) Part {
    return db.parts.get(idx.raw());
}

pub inline fn get_mfr(db: *const DB, idx: Index) ?Manufacturer.Index {
    return db.parts.items(.mfr)[idx.raw()];
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.parts.items(.id)[idx.raw()];
}

pub inline fn get_parent(db: *const DB, idx: Index) ?Index {
    return db.parts.items(.parent)[idx.raw()];
}

pub inline fn get_dist_pns(db: *const DB, idx: Index) []const Distributor_Part_Number {
    return db.parts.items(.dist_pns)[idx.raw()];
}

pub inline fn get_pkg(db: *const DB, idx: Index) ?Package.Index {
    return db.parts.items(.pkg)[idx.raw()];
}

pub fn is_ancestor(db: *const DB, descendant_idx: Index, ancestor_idx: Index) bool {
    const parents = db.parts.items(.parent);
    var maybe_idx: ?Index = descendant_idx;
    var depth: usize = 0;
    while (maybe_idx) |idx| {
        if (idx == ancestor_idx) return true;

        const i = idx.raw();
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
    const i = idx.raw();

    const parents = db.parts.items(.parent);
    for (0.., parents) |child_i, maybe_parent_idx| {
        if (maybe_parent_idx == idx) {
            if (recursive) {
                try delete(db, Index.init(child_i), true);
            } else {
                try set_parent(db, Index.init(child_i), null);
            }
        }
    }

    const mfr = db.parts.items(.mfr)[i];
    const id = db.parts.items(.id)[i];

    std.debug.assert(db.part_lookup.remove(.{ mfr, id }));

    db.parts.items(.dist_pns)[i].deinit(db.container_alloc);

    if (parents[idx.raw()]) |parent_idx| {
        try db.mark_dirty(parent_idx);
    }

    db.parts.set(i, init_empty(null, "", std.time.milliTimestamp()));
    try db.mark_dirty(idx);
}

pub fn set_id(db: *DB, idx: Index, mfr_idx: ?Manufacturer.Index, id: []const u8) !void {
    const i = idx.raw();
    const mfrs = db.parts.items(.mfr);
    const ids = db.parts.items(.id);
    const old_mfr = mfrs[i];
    const old_id = ids[i];
    if (std.meta.eql(old_mfr, mfr_idx) and std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.part_lookup.remove(.{ old_mfr, old_id }));
    try db.part_lookup.putNoClobber(db.container_alloc, .{ mfr_idx, new_id }, idx);
    mfrs[i] = mfr_idx;
    ids[i] = new_id;
    try set_modified(db, idx);

    if (db.loading) return;

    for (0.., db.parts.items(.parent)) |child_i, maybe_parent_idx| {
        if (maybe_parent_idx == idx) {
            try db.mark_dirty(Index.init(child_i));
        }
    }
}

pub fn set_parent(db: *DB, idx: Index, parent_idx: ?Index) !void {
    return set_optional(Index, db, idx, .parent, parent_idx);
}

pub fn set_pkg(db: *DB, idx: Index, pkg_idx: ?Package.Index) !void {
    return set_optional(Package.Index, db, idx, .pkg, pkg_idx);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const created_timestamps = db.parts.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    try set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const modified_timestamps = db.parts.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    try db.mark_dirty(idx);
}

pub fn add_dist_pn(db: *DB, idx: Index, pn: Distributor_Part_Number) !void {
    const i = idx.raw();
    const list: *std.ArrayListUnmanaged(Distributor_Part_Number) = &db.parts.items(.dist_pns)[i];

    for (list.items) |existing_pn| {
        if (existing_pn.eql(pn)) return;
    }

    const interned_pn = try db.intern(pn.pn);

    try db.dist_part_lookup.putNoClobber(db.container_alloc, .{ pn.dist, interned_pn }, idx);

    try list.append(db.container_alloc, .{
        .dist = pn.dist,
        .pn = interned_pn,
    });

    try set_modified(db, idx);
}

pub fn remove_dist_pn(db: *DB, idx: Index, pn: Distributor_Part_Number) !void {
    const i = idx.raw();
    const list: *std.ArrayListUnmanaged(Distributor_Part_Number) = &db.parts.items(.dist_pns)[i];
    
    for (0.., list.items) |list_index, existing_pn| {
        if (existing_pn.eql(pn)) {
            _ = list.orderedRemove(list_index);
            std.debug.assert(db.dist_part_lookup.remove(.{ pn.dist, pn.pn }));
            try set_modified(db, idx);
            break;
        }
    }
}

pub fn edit_dist_pn(db: *DB, idx: Index, old: Distributor_Part_Number, new: Distributor_Part_Number) !void {
    if (old.eql(new)) return;

    const i = idx.raw();
    const list: *std.ArrayListUnmanaged(Distributor_Part_Number) = &db.parts.items(.dist_pns)[i];
    
    for (0.., list.items) |list_index, existing_pn| {
        if (existing_pn.eql(old)) {
            const interned_pn = try db.intern(new.pn);
            std.debug.assert(db.dist_part_lookup.remove(.{ existing_pn.dist, existing_pn.pn }));
            try db.dist_part_lookup.putNoClobber(db.container_alloc, .{ new.dist, interned_pn }, idx);
            list.items[list_index] = .{
                .dist = new.dist,
                .pn = interned_pn,
            };
            try set_modified(db, idx);
            break;
        }
    }
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Part, idx, field, T, raw);
}

fn set_modified(db: *DB, idx: Index) !void {
    try db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
