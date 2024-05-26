pub fn post(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = db.mfr_lookup.get(requested_mfr_name.?) orelse return;
    const mfr_id = db.mfrs.items(.id)[@intFromEnum(idx)];
    const relations = try get_sorted_relations(db, idx);
    const post_prefix = try http.tprint("/mfr:{}", .{ http.percent_encoding.fmtEncoded(mfr_id) });

    var valid_kind = true;
    var valid_other = true;
    var valid_year = true;
    var message: []const u8 = "";

    var relation_kind: ?Manufacturer.Relation.Kind = null;
    var relation_other: []const u8 = "";
    var relation_year: []const u8 = "";
    var expected_index: ?usize = null;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.startsWith(u8, param.name, "relation_kind")) {
            const index_str = param.name["relation_kind".len..];
            const maybe_index = if (index_str.len == 0) null else std.fmt.parseUnsigned(usize, index_str, 10) catch return error.BadRequest;
            if (expected_index != null and !std.meta.eql(expected_index, maybe_index)) {
                log.debug("Index mismatch; expected relation_kind{}, found {s}", .{ expected_index.?, param.name });
                return error.BadRequest;
            }
            expected_index = maybe_index;
            relation_kind = std.meta.stringToEnum(Manufacturer.Relation.Kind, param.value orelse "");

        } else if (std.mem.startsWith(u8, param.name, "relation_other")) {
            const index_str = param.name["relation_other".len..];
            const maybe_index = if (index_str.len == 0) null else std.fmt.parseUnsigned(usize, index_str, 10) catch return error.BadRequest;
            if (expected_index != null and !std.meta.eql(expected_index, maybe_index)) {
                log.debug("Index mismatch; expected relation_other{}, found {s}", .{ expected_index.?, param.name });
                return error.BadRequest;
            }
            expected_index = maybe_index;
            relation_other = try http.temp().dupe(u8, param.value orelse "");

        } else if (std.mem.startsWith(u8, param.name, "relation_year")) {
            const index_str = param.name["relation_year".len..];
            const maybe_index = if (index_str.len == 0) null else std.fmt.parseUnsigned(usize, index_str, 10) catch return error.BadRequest;
            if (expected_index != null and !std.meta.eql(expected_index, maybe_index)) {
                log.debug("Index mismatch; expected relation_year{}, found {s}", .{ expected_index.?, param.name });
                return error.BadRequest;
            }
            expected_index = maybe_index;
            relation_year = try http.temp().dupe(u8, param.value orelse "");
        }
    }

    if (expected_index) |local_index| {
        const rel = relations.items[local_index];
        const db_index = rel.db_index.?;

        if (relation_other.len == 0) {
            // deleting
            try Manufacturer.Relation.remove(db, db_index);
            try req.respond("");
        } else {
            // updating
            const new_kind = relation_kind orelse {
                log.debug("Could not parse relation kind", .{});
                return error.BadRequest;
            };
            const new_other_idx = db.mfr_lookup.get(relation_other) orelse {
                log.debug("Could not find other manufacturer: {s}", .{ relation_other });
                return error.BadRequest;
            };
            const new_year = try validate_year(relation_year, &valid_year, &message);

            if (new_other_idx == idx) {
                message = "Incest is not allowed";
                valid_other = false;
            }

            const valid = valid_kind and valid_other and valid_year;
            var updated = false;
            if (valid) {
                if (try Manufacturer.Relation.set_year(db, db_index, new_year)) updated = true;
                if (rel.is_inverted) {
                    if (try Manufacturer.Relation.set_kind(db, db_index, new_kind.inverse())) updated = true;
                    if (try Manufacturer.Relation.set_source(db, db_index, new_other_idx)) updated = true;
                } else {
                    if (try Manufacturer.Relation.set_kind(db, db_index, new_kind)) updated = true;
                    if (try Manufacturer.Relation.set_target(db, db_index, new_other_idx)) updated = true;
                }
            }
            try req.render("mfr/post_relation.zk", .{
                .valid = valid,
                .saved = updated,
                .err = message,
                .post_prefix = post_prefix,
                .index = local_index,
                .kind = new_kind,
                .kind_str = new_kind.display(),
                .other = db.mfrs.items(.id)[@intFromEnum(new_other_idx)],
                .year = new_year,
                .err_year = !valid,
            }, .{});
        }
    } else {
        // this is the placeholder row
        const new_year = try validate_year(relation_year, &valid_year, &message);

        var new_other_idx: ?Manufacturer.Index = null;
        if (db.mfr_lookup.get(relation_other)) |other_idx| {
            new_other_idx = other_idx;
            relation_other = db.mfrs.items(.id)[@intFromEnum(other_idx)];
            if (new_other_idx == idx) {
                message = "Incest is not allowed";
                valid_other = false;
            }
        }

        if (relation_other.len > 0 and relation_kind == null) {
            valid_kind = false;
            if (message.len == 0) {
                message = "Please select a relation type";
            }
        }

        const relation_kind_str = if (relation_kind) |k| k.display() else "";

        const valid = valid_kind and valid_other and valid_year;
        if (valid and new_other_idx != null) {
            // add new row
            var rel: Manufacturer.Relation = .{
                .source = idx,
                .target = new_other_idx.?,
                .kind = relation_kind.?,
                .year = new_year,
                .source_order_index = @truncate(relations.items.len),
                .target_order_index = 0xFFFF,
            };

            try rel.create(db);

            try req.render("mfr/post_relation.zk", .{
                .valid = true,
                .saved = true,
                .post_prefix = post_prefix,
                .index = relations.items.len,
                .kind = relation_kind.?,
                .kind_str = relation_kind_str,
                .other = relation_other,
                .year = new_year,
            }, .{});

            // include a new placeholder row:
            try req.render("mfr/post_relation_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
        } else {
            // rerender placeholder row
            try req.render("mfr/post_relation_placeholder.zk", .{
                .valid = valid,
                .err_year = !valid_year,
                .err_kind = !valid_kind,
                .err = message,
                .post_prefix = post_prefix,
                .kind = relation_kind,
                .kind_str = relation_kind_str,
                .other = relation_other,
                .year = new_year,
            }, .{});
        }
    }
}

const log = std.log.scoped(.@"http.mfr");

const get_sorted_relations = @import("../../mfr.zig").get_sorted_relations;
const validate_name = @import("../../mfr.zig").validate_name;
const validate_year = @import("../../mfr.zig").validate_year;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
