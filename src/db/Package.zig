mfr: ?Manufacturer.Index,
id: []const u8,
full_name: ?[]const u8,
parent: ?Index,
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

pub fn init_empty(mfr: ?Manufacturer.Index, id: []const u8, timestamp_ms: i64) Package {
    return .{
        .mfr = mfr,
        .id = id,
        .full_name = null,
        .parent = null,
        .notes = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
        .additional_names = .{},
    };
}

pub fn maybe_lookup(db: *const DB, mfr: ?Manufacturer.Index, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.pkg_lookup.get(.{ mfr, name })) |idx| return idx;
    }
    return null;
}

pub fn lookup_multiple(db: *const DB, mfr: ?Manufacturer.Index, possible_names: []const []const u8) ?Index {
    for (possible_names) |name| {
        if (db.pkg_lookup.get(.{ mfr, name })) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, mfr: ?Manufacturer.Index, id: []const u8) !Index {
    if (db.pkg_lookup.get(.{ mfr, id })) |idx| return idx;
    
    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const idx = Index.init(db.pkgs.len);
    const now = std.time.milliTimestamp();
    const pkg = init_empty(mfr, try db.intern(id), now);
    try db.pkgs.append(db.container_alloc, pkg);
    try db.pkg_lookup.putNoClobber(db.container_alloc, .{ mfr, pkg.id }, idx);
    try db.mark_dirty(idx);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Package {
    return db.pkgs.get(idx.raw());
}

pub inline fn get_mfr(db: *const DB, idx: Index) ?Manufacturer.Index {
    return db.pkgs.items(.mfr)[idx.raw()];
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.pkgs.items(.id)[idx.raw()];
}

pub inline fn get_full_name(db: *const DB, idx: Index) ?[]const u8 {
    return db.pkgs.items(.full_name)[idx.raw()];
}

pub inline fn get_parent(db: *const DB, idx: Index) ?Index {
    return db.pkgs.items(.parent)[idx.raw()];
}

pub inline fn get_additional_names(db: *const DB, idx: Index) []const []const u8 {
    return db.pkgs.items(.additional_names)[idx.raw()].items;
}

pub fn is_ancestor(db: *const DB, descendant_idx: Index, ancestor_idx: Index) bool {
    const parents = db.pkgs.items(.parent);
    var maybe_idx: ?Index = descendant_idx;
    var depth: usize = 0;
    while (maybe_idx) |idx| {
        if (idx == ancestor_idx) return true;

        const i = idx.raw();
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
    for (0.., db.parts.items(.pkg)) |part_i, maybe_pkg_idx| {
        if (maybe_pkg_idx == idx) {
            try Part.set_pkg(db, Part.Index.init(part_i), null);
        }
    }

    const i = idx.raw();

    const parents = db.pkgs.items(.parent);
    const maybe_parent_idx = parents[i];
    for (0.., parents) |child_i, maybe_child_parent_idx| {
        if (maybe_child_parent_idx == idx) {
            if (recursive) {
                try delete(db, Index.init(child_i), true);
            } else {
                try set_parent(db, Index.init(child_i), maybe_parent_idx);
            }
        }
    }

    const mfr = db.pkgs.items(.mfr)[i];
    const id = db.pkgs.items(.id)[i];

    std.debug.assert(db.pkg_lookup.remove(.{ mfr, id }));

    if (db.pkgs.items(.full_name)[i]) |full_name| {
        std.debug.assert(db.pkg_lookup.remove(.{ mfr, full_name }));
    }

    const additional_names: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    for (additional_names.items) |name| {
        std.debug.assert(db.pkg_lookup.remove(.{ mfr, name }));
    }
    additional_names.deinit(db.container_alloc);

    if (maybe_parent_idx) |parent_idx| {
        try db.mark_dirty(parent_idx);
    }

    db.pkgs.set(i, init_empty(null, "", std.time.milliTimestamp()));
    try db.mark_dirty(idx);
}

pub fn set_id(db: *DB, idx: Index, mfr_idx: ?Manufacturer.Index, id: []const u8) !void {
    const i = idx.raw();
    const mfrs = db.pkgs.items(.mfr);
    const ids = db.pkgs.items(.id);
    const old_mfr = mfrs[i];
    const old_id = ids[i];
    if (std.meta.eql(old_mfr, mfr_idx) and std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    std.debug.assert(db.pkg_lookup.remove(.{ old_mfr, old_id }));
    try db.pkg_lookup.putNoClobber(db.container_alloc, .{ mfr_idx, new_id }, idx);
    mfrs[i] = mfr_idx;
    ids[i] = new_id;
    try set_modified(db, idx);

    if (!std.meta.eql(old_mfr, mfr_idx)) {
        if (db.pkgs.items(.full_name)[i]) |full_name| {
            std.debug.assert(db.pkg_lookup.remove(.{ old_mfr, full_name }));
            try db.pkg_lookup.putNoClobber(db.container_alloc, .{ mfr_idx, full_name }, idx);
        }

        for (db.pkgs.items(.additional_names)[i].items) |name| {
            std.debug.assert(db.pkg_lookup.remove(.{ old_mfr, name }));
            try db.pkg_lookup.putNoClobber(db.container_alloc, .{ mfr_idx, name }, idx);
        }
    }

    if (db.loading) return;

    for (0.., db.pkgs.items(.parent)) |child_i, maybe_parent_idx| {
        if (maybe_parent_idx == idx) {
            try db.mark_dirty(Index.init(child_i));
        }
    }

    for (0.., db.parts.items(.pkg)) |part_i, maybe_pkg_idx| {
        if (maybe_pkg_idx == idx) {
            try db.mark_dirty(Part.Index.init(part_i));
        }
    }
}

pub fn set_full_name(db: *DB, idx: Index, full_name: ?[]const u8) !void {
    const i = idx.raw();
    const full_names = db.pkgs.items(.full_name);
    const old_name = full_names[i];
    try set_optional([]const u8, db, idx, .full_name, full_name);
    const new_name = full_names[i];
    if (deep.deepEql(old_name, new_name, .Deep)) return;

    const maybe_mfr_idx = db.pkgs.items(.mfr)[i];

    if (old_name) |name| {
        std.debug.assert(db.pkg_lookup.remove(.{ maybe_mfr_idx, name }));
    }
    if (new_name) |name| {
        try db.pkg_lookup.putNoClobber(db.container_alloc, .{ maybe_mfr_idx, name }, idx);
    }
}

pub fn set_parent(db: *DB, idx: Index, parent_idx: ?Index) !void {
    try set_optional(Index, db, idx, .parent, parent_idx);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    try set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const created_timestamps = db.pkgs.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    try set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = idx.raw();
    const modified_timestamps = db.pkgs.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    try db.mark_dirty(idx);
}

pub fn add_additional_names(db: *DB, idx: Index, additional_names: []const []const u8) !void {
    if (additional_names.len == 0) return;

    const i = idx.raw();
    const list: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    try list.ensureUnusedCapacity(db.container_alloc, additional_names.len);

    const maybe_mfr_idx = get_mfr(db, idx);

    var added_name = false;
    for (additional_names) |raw_name| {
        const gop = try db.pkg_lookup.getOrPut(db.container_alloc, .{ maybe_mfr_idx, raw_name });
        if (gop.found_existing) {
            if (idx != gop.value_ptr.*) {
                const ids = db.pkgs.items(.id);
                log.err("Ignoring additional name \"{}\" for package \"{}\" because it is already associated with \"{}\"", .{
                    std.zig.fmtEscapes(raw_name),
                    std.zig.fmtEscapes(ids[idx.raw()]),
                    std.zig.fmtEscapes(ids[gop.value_ptr.raw()]),
                });
            }
        } else {
            const name = try db.intern(raw_name);
            gop.key_ptr.* = .{ maybe_mfr_idx, name };
            gop.value_ptr.* = idx;
            list.appendAssumeCapacity(name);
            added_name = true;
        }
    }

    if (added_name) {
        try set_modified(db, idx);
    }
}

pub fn remove_additional_name(db: *DB, idx: Index, additional_name: []const u8) !void {
    const i = idx.raw();
    const list: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[i];
    
    const maybe_mfr_idx = get_mfr(db, idx);

    for (0.., list.items) |list_index, name| {
        if (std.ascii.eqlIgnoreCase(name, additional_name)) {
            std.debug.assert(db.pkg_lookup.remove(.{ maybe_mfr_idx, name }));
            _ = list.orderedRemove(list_index);
            break;
        }
    } else return;

    try set_modified(db, idx);
}

pub fn rename_additional_name(db: *DB, idx: Index, old_name: []const u8, new_name: []const u8) !void {
    if (std.mem.eql(u8, old_name, new_name)) return;

    const maybe_mfr_idx = get_mfr(db, idx);
    const interned = try db.intern(new_name);

    const list: *std.ArrayListUnmanaged([]const u8) = &db.pkgs.items(.additional_names)[idx.raw()];
    for (0.., list.items) |list_index, name| {
        if (std.mem.eql(u8, name, old_name)) {
            std.debug.assert(db.pkg_lookup.remove(.{ maybe_mfr_idx, old_name }));
            list.items[list_index] = interned;
            break;
        }
    } else {
        try list.append(db.container_alloc, interned);
    }

    try db.pkg_lookup.putNoClobber(db.container_alloc, .{ maybe_mfr_idx, interned }, idx);

    try set_modified(db, idx);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    _ = try db.set_optional(Package, idx, field, T, raw);
}

inline fn set_modified(db: *DB, idx: Index) !void {
    try db.maybe_set_modified(idx);
}

const log = std.log.scoped(.db);

const Manufacturer = DB.Manufacturer;
const Part = DB.Part;
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
