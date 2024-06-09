pub fn post(req: *http.Request, db: *const DB, rnd: *std.rand.Xoshiro256) !void {
    const post_prefix = "/mfr";

    var was_valid = true;

    var valid_kind = true;
    var valid_other = true;
    var valid_year = true;
    var message: []const u8 = "";

    var relation_kind: ?Manufacturer.Relation.Kind = null;
    var relation_other: []const u8 = "";
    var relation_year: []const u8 = "";
    var expected_index_str: ?[]const u8 = null;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            was_valid = false;
            continue;
        }

        var index_str: []const u8 = "";

        if (std.mem.startsWith(u8, param.name, "relation_kind")) {
            index_str = try http.temp().dupe(u8, param.name["relation_kind".len..]);
            relation_kind = std.meta.stringToEnum(Manufacturer.Relation.Kind, param.value orelse "");

        } else if (std.mem.startsWith(u8, param.name, "relation_other")) {
            index_str = try http.temp().dupe(u8, param.name["relation_other".len..]);
            relation_other = try http.temp().dupe(u8, param.value orelse "");

        } else if (std.mem.startsWith(u8, param.name, "relation_year")) {
            index_str = try http.temp().dupe(u8, param.name["relation_year".len..]);
            relation_year = try http.temp().dupe(u8, param.value orelse "");

        } else if (std.mem.startsWith(u8, param.name, "relation")) {
            continue;
        } else {
            log.debug("Unrecognized parameter: {s}", .{ param.name });
            return error.BadRequest;
        }

        if (expected_index_str) |expected| {
            if (!std.mem.eql(u8, expected, index_str)) {
                log.debug("Index mismatch; expected {s}, found {s}", .{ expected, index_str });
                return error.BadRequest;
            }
        }
        expected_index_str = index_str;
    }

    if (expected_index_str == null) {
        log.debug("Index not found!", .{});
        return error.BadRequest;
    }

    if (expected_index_str.?.len > 0) {
        if (relation_other.len == 0) {
            try req.respond("");
        } else {
            const new_kind = relation_kind orelse {
                log.debug("Could not parse relation kind", .{});
                return error.BadRequest;
            };
            const new_other = blk: {
                if (Manufacturer.maybe_lookup(db, relation_other)) |idx| {
                    break :blk Manufacturer.get_id(db, idx);
                } else {
                    valid_other = false;
                    message = "Other manufacturer not found";
                    break :blk relation_other;
                }
            };
            const new_year = try validate_year(relation_year, &valid_year, &message);

            const valid = valid_kind and valid_other and valid_year;

            if (valid != was_valid) {
                try req.add_response_header("hx-trigger", "revalidate");
            }

            try req.render("mfr/post_relation.zk", .{
                .valid = valid,
                .err = message,
                .post_prefix = post_prefix,
                .index = expected_index_str.?,
                .kind = new_kind,
                .kind_str = new_kind.display(),
                .other = new_other,
                .year = new_year,
                .err_year = !valid,
            }, .{});
        }
    } else {
        // this is the placeholder row
        const new_year = try validate_year(relation_year, &valid_year, &message);

        var new_other_idx: ?Manufacturer.Index = null;
        if (Manufacturer.maybe_lookup(db, relation_other)) |other_idx| {
            new_other_idx = other_idx;
            relation_other = Manufacturer.get_id(db, other_idx);
        }

        if (relation_other.len > 0 and relation_kind == null) {
            valid_kind = false;
            if (message.len == 0) {
                message = "Please select a relation type";
            }
        }

        const relation_kind_str = if (relation_kind) |k| k.display() else "";

        const valid = valid_kind and valid_other and valid_year;

        if (valid != was_valid) {
            try req.add_response_header("hx-trigger", "revalidate");
        }

        if (valid and new_other_idx != null) {
            var buf: [16]u8 = undefined;
            rnd.fill(&buf);
            const Base64 = std.base64.url_safe_no_pad.Encoder;
            var new_index: [Base64.calcSize(buf.len)]u8 = undefined;
            _ = Base64.encode(&new_index, &buf);

            try req.render("mfr/post_relation.zk", .{
                .valid = true,
                .post_prefix = post_prefix,
                .index = new_index,
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
