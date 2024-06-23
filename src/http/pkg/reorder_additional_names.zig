pub fn post(req: *http.Request, db: *DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse return;
    const name_list = &db.pkgs.items(.additional_names)[@intFromEnum(idx)];

    var new_list = try std.ArrayList([]const u8).initCapacity(http.temp(), name_list.items.len);
    var apply_changes = true;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const expected_prefix = "additional_name_order";
        if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
        const index_str = param.name[expected_prefix.len..];
        if (index_str.len == 0) continue;
        const index = std.fmt.parseUnsigned(usize, index_str, 10) catch {
            apply_changes = false;
            break;
        };
        if (index >= name_list.items.len) {
            apply_changes = false;
        }

        try new_list.append(name_list.items[index]);
    }

    if (apply_changes and new_list.items.len == name_list.items.len) {
        @memcpy(name_list.items, new_list.items);
    }

    const post_prefix = try Transaction.get_post_prefix(db, idx);
    for (0.., name_list.items) |i, name| {
        try req.render("common/post_additional_name.zk", .{
            .valid = true,
            .post_prefix = post_prefix,
            .index = i,
            .name = name,
        }, .{});
    }
    try req.render("common/post_additional_name_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
}

const Transaction = @import("Transaction.zig");
const Package = DB.Package;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
