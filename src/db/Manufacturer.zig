id: []const u8,
full_name: []const u8,
country: ?[]const u8,
website: ?[]const u8,
wiki: ?[]const u8,
notes: ?[]const u8,
created_timestamp_ms: i64,
modified_timestamp_ms: i64,

additional_names: std.ArrayListUnmanaged([]const u8),

// Alternative names
// Related mfrs
// Attachments/Images
// Parts tagged with this mfr

pub const Index = enum (u32) { _ };

pub fn set_full_name(db: *DB, idx: Index, full_name: []const u8) !void {
    const i = @intFromEnum(idx);
    const full_names = db.mfrs.items(.full_name);
    if (std.mem.eql(u8, full_name, full_names[i])) return;
    full_names[i] = try db.intern(full_name);
    set_modified(db, idx);
}

pub fn set_country(db: *DB, idx: Index, country: ?[]const u8) !void {
    return set_optional_string(db, idx, .country, country);
}

pub fn set_website(db: *DB, idx: Index, url: ?[]const u8) !void {
    return set_optional_string(db, idx, .website, url);
}

pub fn set_wiki(db: *DB, idx: Index, url: ?[]const u8) !void {
    return set_optional_string(db, idx, .wiki, url);
}

pub fn set_notes(db: *DB, idx: Index, notes: ?[]const u8) !void {
    return set_optional_string(db, idx, .notes, notes);
}

pub fn set_created_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const created_timestamps = db.mfrs.items(.created_timestamp_ms);
    if (timestamp_ms == created_timestamps[i]) return;
    created_timestamps[i] = timestamp_ms;
    set_modified(db, idx);
}

pub fn set_modified_time(db: *DB, idx: Index, timestamp_ms: i64) !void {
    const i = @intFromEnum(idx);
    const modified_timestamps = db.mfrs.items(.modified_timestamp_ms);
    if (timestamp_ms == modified_timestamps[i]) return;
    modified_timestamps[i] = timestamp_ms;
    db.mark_dirty(timestamp_ms);
}

pub const Add_Additional_Names_Options = struct {
    set_modified_on_added: bool = false,
    set_modified_on_ignore: bool = false,
};
pub fn add_additional_names(db: *DB, idx: Index, additional_names: []const []const u8, options: Add_Additional_Names_Options) !void {
    if (additional_names.len == 0) return;

    const i = @intFromEnum(idx);
    const list: *std.ArrayListUnmanaged([]const u8) = &db.mfrs.items(.additional_names)[i];
    try list.ensureUnusedCapacity(db.container_alloc, additional_names.len);

    for (additional_names) |raw_name| {
        const gop = try db.mfr_lookup.getOrPut(db.container_alloc, raw_name);
        if (gop.found_existing) {
            if (idx != gop.value_ptr.*) {
                const ids = db.mfrs.items(.id);
                log.err("Ignoring additional name \"{s}\" for manufacturer \"{s}\" because it is already associated with \"{s}\"", .{
                    raw_name,
                    ids[@intFromEnum(idx)],
                    ids[@intFromEnum(gop.value_ptr.*)],
                });
            }
            if (options.set_modified_on_ignore) set_modified(db, idx);
        } else {
            const name = try db.intern(raw_name);
            gop.key_ptr.* = name;
            gop.value_ptr.* = idx;
            list.appendAssumeCapacity(name);
            if (options.set_modified_on_added) set_modified(db, idx);
        }
    }
}

fn set_optional_string(db: *DB, idx: Index, comptime field: @TypeOf(.enum_field), raw: ?[]const u8) !void {
    const i = @intFromEnum(idx);
    const array = db.mfrs.items(field);
    if (array[i]) |current| {
        if (raw) |new| {
            if (!std.mem.eql(u8, current, new)) {
                array[i] = try db.intern(new);
                set_modified(db, idx);
            }
        } else {
            // removing
            array[i] = null;
            set_modified(db, idx);
        }
    } else {
        if (raw) |new| {
            // adding
            array[i] = try db.intern(new);
            set_modified(db, idx);
        }
    }
}

fn set_modified(db: *DB, idx: Index) void {
    const i = @intFromEnum(idx);
    const now = std.time.milliTimestamp();
    db.mfrs.items(.modified_timestamp_ms)[i] = now;
    db.mark_dirty(now);
}

const log = std.log.scoped(.db);

const DB = @import("../DB.zig");
const std = @import("std");
