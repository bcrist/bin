id: Manufacturer_And_Part = .{},
parent: ?Manufacturer_And_Part = null,
child: []const Manufacturer_And_Part = &.{},
pkg: ?[]const u8 = null,
notes: ?[]const u8 = null,
dist_pn: []const Distributor_Part_Number = &.{},
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const Manufacturer_And_Part = struct {
    mfr: ?[]const u8 = "",
    id: []const u8 = "",

    pub const context = struct {
        pub const inline_fields = &.{ "mfr", "id" };
    };
};

const Distributor_Part_Number = struct {
    dist: []const u8 = "",
    pn: []const u8 = "",

    pub const context = struct {
        pub const inline_fields = &.{ "dist", "pn" };
    };
};

const SX_Part = @This();

pub const context = struct {
    pub const inline_fields = &.{ "id" };
    pub const id = Manufacturer_And_Part.context;
    pub const parent = Manufacturer_And_Part.context;
    pub const child = Manufacturer_And_Part.context;
    pub const dist_pn = Distributor_Part_Number.context;
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Part.Index) !SX_Part {
    const ids = db.parts.items(.id);
    const mfrs = db.parts.items(.mfr);
    const mfr_ids = db.mfrs.items(.id);
    const dist_ids = db.dists.items(.id);
    
    var children = std.ArrayList(Manufacturer_And_Part).init(temp);
    for (0.., db.parts.items(.parent)) |child_i, parent_idx| {
        if (parent_idx == idx) {
            try children.append(.{
                .mfr = if (mfrs[child_i]) |mfr_idx| mfr_ids[@intFromEnum(mfr_idx)] else null,
                .id = ids[child_i],
            });
        }
    }

    const data = Part.get(db, idx);

    const dist_pns = try temp.alloc(Distributor_Part_Number, data.dist_pns.items.len);
    for (data.dist_pns.items, dist_pns) |src, *dest| {
        dest.* = .{
            .dist = dist_ids[@intFromEnum(src.dist)],
            .pn = src.pn,
        };
    }

    const id: Manufacturer_And_Part = .{
        .mfr = if (data.mfr) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null,
        .id = data.id,
    };

    const parent: ?Manufacturer_And_Part = if (data.parent) |parent_idx| .{
        .mfr = if (Part.get_mfr(db, parent_idx)) |mfr_idx| Manufacturer.get_id(db, mfr_idx) else null,
        .id = Part.get_id(db, parent_idx),
    } else null;

    const pkg_id = if (data.pkg) |pkg_idx| Package.get_id(db, pkg_idx) else null;
    return .{
        .id = id,
        .parent = parent,
        .child = children.items,
        .pkg = pkg_id,
        .notes = data.notes,
        .dist_pn = dist_pns,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
    };
}

pub fn read(self: SX_Part, db: *DB) !void {
    const id = std.mem.trim(u8, self.id.id, &std.ascii.whitespace);

    if (!DB.is_valid_id(id)) {
        log.warn("Skipping Part {s} (invalid ID)", .{ id });
        return;
    }

    var mfr_idx: ?Manufacturer.Index = null;
    if (self.id.mfr) |mfr_id| {
        mfr_idx = try Manufacturer.lookup_or_create(db, mfr_id);
    }

    const idx = try Part.lookup_or_create(db, mfr_idx, id);

    if (self.parent) |parent| {
        const parent_mfr_idx = if (parent.mfr) |mfr_id| try Manufacturer.lookup_or_create(db, mfr_id) else null;
        const parent_idx = try Part.lookup_or_create(db, parent_mfr_idx, parent.id);
        _ = try Part.set_parent(db, idx, parent_idx);
    }

    if (self.pkg) |pkg_id| {
        const pkg_idx = try Package.lookup_or_create(db, pkg_id);
        _ = try Part.set_pkg(db, idx, pkg_idx);
    }

    for (self.dist_pn) |pn| {
        try Part.add_dist_pn(db, idx, .{
            .dist = try Distributor.lookup_or_create(db, pn.dist),
            .pn = pn.pn,
        });
    }

    if (self.notes) |notes| try Part.set_notes(db, idx, notes);

    if (self.created) |dto| try Part.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Part.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.parts.len));
    defer filenames.clearRetainingCapacity();

    const dirty_timestamp_ms = db.dirty_timestamp_ms orelse std.time.milliTimestamp();

    var dir = try root.makeOpenPath("p", .{ .iterate = true });
    defer dir.close();

    for (0..db.parts.len, db.parts.items(.id), db.parts.items(.modified_timestamp_ms)) |i, id, modified_ts| {
        const dest_path = try paths.unique_path(allocator, id, filenames);
        
        if (modified_ts < dirty_timestamp_ms) continue;

        const DTO = Date_Time.With_Offset;
        const modified_dto = DTO.from_timestamp_ms(modified_ts, null);
        log.info("Writing p{s}{s} (modified {" ++ DTO.fmt_sql_ms ++ "})", .{ std.fs.path.sep_str, dest_path, modified_dto });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("part");
        try sxw.object(try SX_Part.init(allocator, db, @enumFromInt(i)), SX_Part.context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "p" ++ std.fs.path.sep_str);
}

const log = std.log.scoped(.db);

const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const Package = DB.Package;
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
