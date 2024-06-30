id: []const u8 = "",
full_name: ?[]const u8 = null,
additional_names: []const []const u8 = &.{},
url: ?[]const u8 = null,
wiki: ?[]const u8 = null,
country: ?[]const u8 = null,
founded: ?u16 = null,
suspended: ?u16 = null,
rel: []const Relation = &.{},
notes: ?[]const u8 = null,
created: ?Date_Time.With_Offset = null,
modified: ?Date_Time.With_Offset = null,

const SX_Distributor = @This();

pub const Relation = struct {
    kind: Distributor.Relation.Kind = .formerly,
    other: []const u8 = "",
    year: ?u16 = null,
};

pub const context = struct {
    pub const inline_fields = &.{ "id", "full_name", "additional_names" };
    pub const created = Date_Time.With_Offset.fmt_sql;
    pub const modified = Date_Time.With_Offset.fmt_sql;

    pub const rel = struct {
        pub const inline_fields = &.{ "kind", "other", "year" };
    };
};

pub fn init(temp: std.mem.Allocator, db: *const DB, idx: Distributor.Index) !SX_Distributor {
    var temp_rels = std.ArrayList(Distributor.Relation).init(temp);
    defer temp_rels.deinit();

    for (0.., db.dist_relations.items(.source), db.dist_relations.items(.target)) |rel_i, source, target| {
        if (source == idx) {
            try temp_rels.append(db.dist_relations.get(rel_i));
        } else if (target == idx) {
            try temp_rels.append(db.dist_relations.get(rel_i).inverse());
        }
    }

    std.sort.block(Distributor.Relation, temp_rels.items, {}, Distributor.Relation.source_less_than);

    const rels = try temp.alloc(Relation, temp_rels.items.len);
    for (rels, temp_rels.items) |*out, in| {
        const other = if (in.source == idx) in.target else in.source;
        out.* = .{
            .kind = in.kind,
            .other = Distributor.get_id(db, other),
            .year = in.year,
        };
    }

    const data = Distributor.get(db, idx);
    var full_name = data.full_name;
    if (data.additional_names.items.len > 0 and full_name == null) {
        full_name = data.id;
    }

    return .{
        .id = data.id,
        .full_name = full_name,
        .additional_names = data.additional_names.items,
        .url = data.website,
        .wiki = data.wiki,
        .country = data.country,
        .notes = data.notes,
        .founded = data.founded_year,
        .suspended = data.suspended_year,
        .created = Date_Time.With_Offset.from_timestamp_ms(data.created_timestamp_ms, null),
        .modified = Date_Time.With_Offset.from_timestamp_ms(data.modified_timestamp_ms, null),
        .rel = rels,
    };
}

pub fn read(self: SX_Distributor, db: *DB) !void {
    const id = std.mem.trim(u8, self.id, &std.ascii.whitespace);

    var full_name = self.full_name;
    if (self.full_name) |name| {
        if (std.mem.eql(u8, id, name)) {
            full_name = null;
        }
    }

    const idx = Distributor.maybe_lookup(db, full_name)
        orelse Distributor.lookup_multiple(db, self.additional_names)
        orelse try Distributor.lookup_or_create(db, id);

    _ = try Distributor.set_id(db, idx, id);
    if (full_name) |name| try Distributor.set_full_name(db, idx, name);
    if (self.country) |country| try Distributor.set_country(db, idx, country);
    if (self.url) |url| try Distributor.set_website(db, idx, url);
    if (self.wiki) |wiki| try Distributor.set_wiki(db, idx, wiki);
    if (self.notes) |notes| try Distributor.set_notes(db, idx, notes);
    if (self.founded) |year| try Distributor.set_founded_year(db, idx, year);
    if (self.suspended) |year| try Distributor.set_suspended_year(db, idx, year);
    try Distributor.add_additional_names(db, idx, self.additional_names);

    for (0.., self.rel) |order_index, rel_info| {
        const other_idx = try Distributor.lookup_or_create(db, rel_info.other);
        const rel_idx = try Distributor.Relation.lookup_or_create(db, idx, other_idx, rel_info.kind, rel_info.year);
        try Distributor.Relation.set_order_index(db, idx, rel_idx, @intCast(order_index));
    }

    if (self.created) |dto| try Distributor.set_created_time(db, idx, dto.timestamp_ms());
    if (self.modified) |dto| try Distributor.set_modified_time(db, idx, dto.timestamp_ms());
}

pub fn write_dirty(allocator: std.mem.Allocator, db: *DB, root: *std.fs.Dir, filenames: *paths.StringHashSet) !void {
    try filenames.ensureUnusedCapacity(@intCast(db.dists.len));
    defer filenames.clearRetainingCapacity();

    var dir = try root.makeOpenPath("dist", .{ .iterate = true });
    defer dir.close();

    for (0.., db.dists.items(.id)) |i, id| {
        const dest_path = try paths.unique_path(allocator, id, filenames);
        const idx = Distributor.Index.init(i);
        
        if (!db.dirty_set.contains(idx.any())) continue;

        log.info("Writing dist{s}{s}", .{ std.fs.path.sep_str, dest_path });

        var af = try dir.atomicFile(dest_path, .{});
        defer af.deinit();

        var sxw = sx.writer(allocator, af.file.writer().any());
        defer sxw.deinit();

        try sxw.expression("version");
        try sxw.int(1, 10);
        try sxw.close();

        try sxw.expression_expanded("dist");
        try sxw.object(try init(allocator, db, idx), context);
        try sxw.close();

        try af.finish();
    }

    try paths.delete_all_except(&dir, filenames.*, "dist" ++ std.fs.path.sep_str);
}

const log = std.log.scoped(.db);

const Distributor = @import("../Distributor.zig");
const DB = @import("../../DB.zig");
const paths = @import("../paths.zig");
const Date_Time = tempora.Date_Time;
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
