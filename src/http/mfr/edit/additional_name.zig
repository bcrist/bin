pub fn post(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;
    const mfr_id = Manufacturer.get_id(db, idx);
    const name_list = &db.mfrs.items(.additional_names)[@intFromEnum(idx)];
    const post_prefix = try http.tprint("/mfr:{}", .{ http.percent_encoding.fmtEncoded(mfr_id) });

    var valid = true;
    var message: []const u8 = "";

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const str_value = param.value orelse "";

        const expected_prefix = "additional_name";
        if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
        const index_str = param.name[expected_prefix.len..];
        const maybe_index: ?usize = if (index_str.len == 0) null else std.fmt.parseUnsigned(usize, index_str, 10) catch return error.BadRequest;

        const new_name = if (str_value.len == 0) str_value else try validate_name(str_value, db, idx, .{ .additional_name = maybe_index }, &valid, &message) orelse "";

        if (maybe_index) |index| {
            if (new_name.len == 0) {
                if (valid) {
                    try Manufacturer.remove_additional_name(db, idx, name_list.items[index]);
                }
                try req.respond("");
            } else {
                if (valid) {
                    try Manufacturer.rename_additional_name(db, idx, name_list.items[index], new_name);
                }
                try req.render("mfr/post_additional_name.zk", .{
                    .valid = valid,
                    .saved = valid,
                    .err = message,
                    .post_prefix = post_prefix,
                    .index = index,
                    .name = new_name,
                }, .{});
            }
        } else {
            // this is the placeholder row
            if (new_name.len == 0) {
                try req.render("mfr/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
            } else {
                if (valid) {
                    const new_index = name_list.items.len;
                    log.debug("Adding new additional name {s} at index {}", .{ new_name, new_index });
                    try Manufacturer.add_additional_names(db, idx, &.{ new_name });
                    try req.render("mfr/post_additional_name.zk", .{
                        .valid = true,
                        .saved = true,
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
