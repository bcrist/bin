id: []const u8,
full_name: ?[]const u8,
country: ?[]const u8,
website: ?[]const u8,
wiki: ?[]const u8,
notes: ?[]const u8,
founded_year: ?u16,
suspended_year: ?u16,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,
additional_names: std.ArrayListUnmanaged([]const u8),

// Attachments/Images
// orders tagged with this distributor

const Distributor = @This();
pub const Index = enum (u32) {
    _,

    pub const Type = Distributor;
};

pub fn init_empty(id: []const u8, timestamp_ms: i64) Distributor {
    return .{
        .id = id,
        .full_name = null,
        .country = null,
        .website = null,
        .wiki = null,
        .notes = null,
        .founded_year = null,
        .suspended_year = null,
        .created_timestamp_ms = timestamp_ms,
        .modified_timestamp_ms = timestamp_ms,
        .additional_names = .{},
    };
}

pub fn maybe_lookup(db: *const DB, possible_name: ?[]const u8) ?Index {
    if (possible_name) |name| {
        if (db.dist_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_multiple(db: *const DB, possible_names: []const []const u8) ?Index {
    for (possible_names) |name| {
        if (db.dist_lookup.get(name)) |idx| return idx;
    }
    return null;
}

pub fn lookup_or_create(db: *DB, id: []const u8) !Index {
    if (db.dist_lookup.get(id)) |idx| return idx;
    
    const idx: Index = @enumFromInt(db.dists.len);
    const now = std.time.milliTimestamp();
    const dist = init_empty(try db.intern(id), now);
    try db.dists.append(db.container_alloc, dist);
    try db.dist_lookup.putNoClobber(db.container_alloc, dist.id, idx);
    db.mark_dirty(now);
    return idx;
}

pub inline fn get(db: *const DB, idx: Index) Distributor {
    return db.dists.get(@intFromEnum(idx));
}

pub inline fn get_id(db: *const DB, idx: Index) []const u8 {
    return db.dists.items(.id)[@intFromEnum(idx)];
}

pub inline fn get_full_name(db: *const DB, idx: Index) ?[]const u8 {
    return db.dists.items(.full_name)[@intFromEnum(idx)];
}

pub inline fn get_additional_names(db: *const DB, idx: Index) []const []const u8 {
    return db.dists.items(.additional_names)[@intFromEnum(idx)].items;
}

pub fn delete(db: *DB, idx: Index) !void {
    // @Speed: this is pretty slow, but deleting distributors isn't something that needs to be done often,
    // so probably not worth adding an acceleration structure for looking up part numbers by distributor.
    for (0.., db.parts.items(.dist_pns)) |part_idx, dist_pns| {
        var i = dist_pns.items.len;
        while (i > 0) {
            i -= 1;
            const pn = dist_pns.items[i];
            if (pn.dist == idx) {
                try Part.remove_dist_pn(db, @enumFromInt(part_idx), pn);
            }
        }
    }

    const i = @intFromEnum(idx);
    std.debug.assert(db.dist_lookup.remove(db.dists.items(.id)[i]));

    if (db.dists.items(.full_name)[i]) |full_name| {
        std.debug.assert(db.dist_lookup.remove(full_name));
    }

    const additional_names: *std.ArrayListUnmanaged([]const u8) = &db.dists.items(.additional_names)[i];
    for (additional_names.items) |name| {
        std.debug.assert(db.dist_lookup.remove(name));
    }
    additional_names.deinit(db.container_alloc);

    var relation: usize = 0;
    var relation_source = db.dist_relations.items(.source);
    var relation_target = db.dist_relations.items(.target);
    while (relation < db.dist_relations.len) : (relation += 1) {
        if (relation_source[relation] == idx or relation_target[relation] == idx) {
            db.dist_relations.swapRemove(relation);
            relation -= 1;
            relation_source = db.dist_relations.items(.source);
            relation_target = db.dist_relations.items(.target);
        }
    }

    const now = std.time.milliTimestamp();
    db.dists.set(i, init_empty("", now));
    db.mark_dirty(now);
}

pub fn set_id(db: *DB, idx: Index, id: []const u8) !void {
    const i = @intFromEnum(idx);
    const ids = db.dists.items(.id);
    const old_id = ids[i];
    if (std.mem.eql(u8, id, old_id)) return;

    if (!DB.is_valid_id(id)) return error.Invalid_ID;

    const new_id = try db.intern(id);
    log.debug("Changing {} ID from {s} to {s}", .{ idx, old_id, new_id });
    std.debug.assert(db.dist_lookup.remove(old_id));
    try db.dist_lookup.putNoClobber(db.container_alloc, new_id, idx);
    ids[i] = new_id;
    set_modified(db, idx);
}

pub fn set_full_name(db: *DB, idx: Index, full_name: ?[]const u8) !void {
    const i = @intFromEnum(idx);
    const full_names = db.dists.items(.full_name);
    const old_name = full_names[i];
    try set_optional([]const u8, db, idx, .full_name, full_name);
    const new_name = full_names[i];
    if (deep.deepEql(old_name, new_name, .Deep)) return;

    if (old_name) |name| {
        std.debug.assert(db.dist_lookup.remove(name));
    }
    if (new_name) |name| {
        try db.dist_lookup.putNoClobber(db.container_alloc, name, idx);
    }
}

pub fn set_country(db: *DB, idx: Index, country: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .country, country);
}

pub fn set_website(db: *DB, idx: Index, url: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .website, url);
}

pub fn set_wiki(db: *DB, idx: Index, url: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .wiki, url);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional([]const u8, db, idx, .notes, notes);
}

pub fn set_founded_year(db: *DB, idx: Index, year: ?u16) !void {
    return set_optional(u16, db, idx, .founded_year, year);
}

pub fn set_suspended_year(db: *DB, idx: Index, year: ?u16) !void {
    return set_optional(u16, db, idx, .suspended_year, year);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const created_timestamps = db.dists.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const modified_timestamps = db.dists.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    db.mark_dirty(timestamp_ms);
}

pub fn add_additional_names(db: *DB, idx: Index, additional_names: []const []const u8) !void {
    if (additional_names.len == 0) return;

    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged([]const u8) = &db.dists.items(.additional_names)[i];
    try list.ensureUnusedCapacity(db.container_alloc, additional_names.len);

    var added_name = false;

    for (additional_names) |raw_name| {
        const gop = try db.dist_lookup.getOrPut(db.container_alloc, raw_name);
        if (gop.found_existing) {
            if (idx != gop.value_ptr.*) {
                const ids = db.dists.items(.id);
                log.err("Ignoring additional name \"{}\" for distributor \"{}\" because it is already associated with \"{}\"", .{
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
    const list: *std.ArrayListUnmanaged([]const u8) = &db.dists.items(.additional_names)[i];
    
    for (0.., list.items) |list_index, name| {
        if (std.mem.eql(u8, name, additional_name)) {
            std.debug.assert(db.dist_lookup.remove(name));
            _ = list.orderedRemove(list_index);
            break;
        }
    } else return;

    set_modified(db, idx);
}

pub fn rename_additional_name(db: *DB, idx: Index, old_name: []const u8, new_name: []const u8) !void {
    if (std.mem.eql(u8, old_name, new_name)) return;

    const interned = try db.intern(new_name);
    try db.dist_lookup.putNoClobber(db.container_alloc, interned, idx);

    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged([]const u8) = &db.dists.items(.additional_names)[i];
    
    for (0.., list.items) |list_index, name| {
        if (std.mem.eql(u8, name, old_name)) {
            std.debug.assert(db.dist_lookup.remove(old_name));
            list.items[list_index] = interned;
            break;
        }
    } else {
        try list.append(db.container_alloc, interned);
    }

    set_modified(db, idx);
}

fn set_optional(comptime T: type, db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?T) !void {
    try db.set_optional(Distributor, idx, field, T, raw);
}

fn set_modified(db: *DB, idx: Index) void {
    db.maybe_set_modified(idx);
}

pub const Relation = struct {
    source: Distributor.Index,
    target: Distributor.Index,
    kind: Kind,
    year: ?u16,
    source_order_index: u16,
    target_order_index: u16,

    pub const Index = enum (u32) { _ };

    pub const Kind = enum (u8) {
        formerly = 0,
        latterly = 1,

        subsidiary = 2,
        subsidiary_of = 3,

        spun_off = 4,
        spun_off_from = 5,

        absorbed = 6,
        absorbed_by = 7,

        partially_absorbed = 8,
        partially_absorbed_by = 9,

        pub fn is_canonical(self: Kind) bool {
            return (@intFromEnum(self) & 1) == 0;
        }

        pub fn inverse(self: Kind) Kind {
            return @enumFromInt(@intFromEnum(self) ^ 1);
        }

        pub fn display(self: Kind) []const u8 {
            return switch (self) {
                .formerly => "Formerly:",
                .latterly => "Latterly:",
                .subsidiary => "Subsidiary:",
                .subsidiary_of => "Subsidiary of",
                .spun_off => "Spun off:",
                .spun_off_from => "Spun off from",
                .absorbed => "Absorbed:",
                .absorbed_by => "Absorbed by",
                .partially_absorbed => "Partially absorbed:",
                .partially_absorbed_by => "Partially absorbed by",
            };
        }
    };

    pub fn lookup_or_create(db: *DB, source: Distributor.Index, target: Distributor.Index, kind: Kind, year: ?u16) !Relation.Index {
        const s = db.dist_relations.slice();
        const inverse_kind = kind.inverse();
        for (0.., s.items(.source), s.items(.target), s.items(.kind), s.items(.year)) |i, src, t, k, y| {
            if (!std.meta.eql(y, year)) continue;
            if (src == source and t == target and k == kind) return @enumFromInt(i);
            if (src == target and t == source and k == inverse_kind) return @enumFromInt(i);
        }

        const rel: Relation = .{
            .source = source,
            .target = target,
            .kind = kind,
            .year = year,
            .source_order_index = 0,
            .target_order_index = 0,
        };
        
        return try rel.create(db);
    }

    pub fn inverse(self: Relation) Relation {
        return .{
            .source = self.target,
            .target = self.source,
            .kind = self.kind.inverse(),
            .year = self.year,
            .source_order_index = self.target_order_index,
            .target_order_index = self.source_order_index,
        };
    }

    pub fn canonical(self: Relation) Relation {
        return if (self.kind.is_canonical()) self else self.inverse();
    }

    pub fn create(self: Relation, db: *DB) !Relation.Index {
        const i: Relation.Index = @enumFromInt(db.dist_relations.len);
        try db.dist_relations.append(db.container_alloc, self.canonical());
        set_modified(db, self.source);
        set_modified(db, self.target);
        return i;
    }

    pub fn remove(db: *DB, idx: Relation.Index) !void {
        const i = @intFromEnum(idx);
        set_modified_relation(db, idx);
        db.dist_relations.swapRemove(i);
    }

    pub fn maybe_remove(db: *DB, source: Distributor.Index, target: Distributor.Index, kind: Kind, year: ?u16) !void {
        const s = db.dist_relations.slice();
        const inverse_kind = kind.inverse();
        for (0.., s.items(.source), s.items(.target), s.items(.kind), s.items(.year)) |i, src, t, k, y| {
            if (!std.meta.eql(y, year)) continue;
            if (src == source and t == target and k == kind) {
                return try remove(db, @enumFromInt(i));
            }
            if (src == target and t == source and k == inverse_kind) {
                return try remove(db, @enumFromInt(i));
            }
        }
    }

    pub inline fn get_source(db: *DB, idx: Relation.Index) Distributor.Index {
        return db.dist_relations.items(.source)[@intFromEnum(idx)];
    }

    pub inline fn get_target(db: *DB, idx: Relation.Index) Distributor.Index {
        return db.dist_relations.items(.target)[@intFromEnum(idx)];
    }

    pub fn set_kind(db: *DB, idx: Relation.Index, kind: Kind) !void {
        const i = @intFromEnum(idx);
        const kinds = db.dist_relations.items(.kind);
        const current = kinds[i];
        if (current != kind) {
            kinds[i] = kind;
            log.debug("Changed kind for {} from {s} to {s}", .{ idx, @tagName(current), @tagName(kind) });
            set_modified_relation(db, idx);
        }
    }

    pub fn set_source(db: *DB, idx: Relation.Index, source: Distributor.Index) !void {
        const i = @intFromEnum(idx);
        const sources = db.dist_relations.items(.source);
        const current = sources[i];
        if (current != source) {
            sources[i] = source;
            log.debug("Changed source for {} from {} to {}", .{ idx, @intFromEnum(current), @intFromEnum(source) });
            set_modified_relation(db, idx);
            set_modified(db, current);
        }
    }

    pub fn set_target(db: *DB, idx: Relation.Index, target: Distributor.Index) !void {
        const i = @intFromEnum(idx);
        const targets = db.dist_relations.items(.target);
        const current = targets[i];
        if (current != target) {
            targets[i] = target;
            log.debug("Changed target for {} from {} to {}", .{ idx, @intFromEnum(current), @intFromEnum(target) });
            set_modified_relation(db, idx);
            set_modified(db, current);
        }
    }

    pub fn set_year(db: *DB, idx: Relation.Index, year: ?u16) !void {
        const i = @intFromEnum(idx);
        const years = db.dist_relations.items(.year);
        if (years[i]) |current| {
            if (year) |new| {
                if (current != new) {
                    years[i] = new;
                    log.debug("Changed year for {} from {} to {}", .{ idx, current, new });
                    set_modified_relation(db, idx);
                }
            } else {
                years[i] = null;
                log.debug("Removed year from {}", .{ idx });
                set_modified_relation(db, idx);
            }
        } else {
            if (year) |new| {
                years[i] = new;
                log.debug("Assigned year for {} to {}", .{ idx, new });
                set_modified_relation(db, idx);
            }
        }
    }

    pub fn set_order_index(db: *DB, dist_idx: Distributor.Index, idx: Relation.Index, order_index: u16) !void {
        const i = @intFromEnum(idx);
        const s = db.dist_relations.slice();
        const order_indices = if (s.items(.source)[i] == dist_idx)
            s.items(.source_order_index)
        else if (s.items(.target)[i] == dist_idx)
            s.items(.target_order_index)
        else unreachable;

        const old_order_index = order_indices[i];
        if (old_order_index == order_index) return;

        order_indices[i] = order_index;
        log.debug("Changed order_index for {} from {} to {}", .{ idx, old_order_index, order_index });
        set_modified(db, dist_idx);
    }

    pub fn source_less_than(_: void, a: Relation, b: Relation) bool {
        return a.source_order_index < b.source_order_index;
    }

    fn set_modified_relation(db: *DB, idx: Relation.Index) void {
        const i = @intFromEnum(idx);
        set_modified(db, db.dist_relations.items(.source)[i]);
        set_modified(db, db.dist_relations.items(.target)[i]);
    }
};

const log = std.log.scoped(.db);

const Part = DB.Part;
const DB = @import("../DB.zig");
const deep = @import("deep_hash_map");
const std = @import("std");
