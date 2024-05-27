pub fn post(req: *http.Request, db: *const DB, rnd: *std.rand.Xoshiro256) !void {
    const post_prefix = "/mfr";

    var was_valid = true;
    var valid = true;
    var message: []const u8 = "";

    var index_str: []const u8 = "";
    var new_name: []const u8 = "";

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            was_valid = false;
            continue;
        }

        const expected_prefix = "additional_name";
        if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
        index_str = try http.temp().dupe(u8, param.name[expected_prefix.len..]);
        const str_value = try http.temp().dupe(u8, param.value orelse "");

        new_name = try validate_name(str_value, db, null, .{ .additional_name = null }, &valid, &message);
    }

    if (was_valid != valid) {
        try req.add_response_header("hx-trigger", "revalidate");
    }

    if (index_str.len > 0) {
        if (new_name.len == 0) {
            try req.respond("");
        } else {
            try req.render("mfr/post_additional_name.zk", .{
                .valid = valid,
                .err = message,
                .post_prefix = post_prefix,
                .index = index_str,
                .name = new_name,
            }, .{});
        }
    } else {
        // this is the placeholder row
        if (new_name.len == 0) {
            try req.render("mfr/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
        } else {
            if (valid) {
                var buf: [16]u8 = undefined;
                rnd.fill(&buf);
                const Base64 = std.base64.url_safe_no_pad.Encoder;
                var new_index: [Base64.calcSize(buf.len)]u8 = undefined;
                _ = Base64.encode(&new_index, &buf);

                try req.render("mfr/post_additional_name.zk", .{
                    .valid = true,
                    .post_prefix = post_prefix,
                    .index = new_index,
                    .name = new_name,
                }, .{});
                try req.render("mfr/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
            } else {
                try req.render("mfr/post_additional_name_placeholder.zk", .{
                    .valid = false,
                    .err = message,
                    .post_prefix = post_prefix,
                    .name = new_name,
                }, .{});
            }
        }
    }
}

const log = std.log.scoped(.@"http.mfr");

const validate_name = @import("../../mfr.zig").validate_name;
const validate_year = @import("../../mfr.zig").validate_year;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
