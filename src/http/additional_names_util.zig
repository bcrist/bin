pub const Render_Results_Options = struct {
    rnd: ?*std.rand.Xoshiro256,
    target_index: ?[]const u8,
    post_prefix: []const u8,
};

pub fn render_results(req: *http.Request, txn: anytype, options: Render_Results_Options) !void {
    const changes_applied: bool = txn.changes_applied;
    
    var name_index: usize = 0;
    for (txn.additional_names.keys(), txn.additional_names.values()) |index_str, data| {
        const is_target = if (options.target_index) |target_index|
            std.mem.eql(u8, index_str, target_index)
        else false;
        
        const is_changed = data.is_changed();

        const is_index_changed = if (txn.idx != null and index_str.len > 0) is_index_changed: {
            const old_name_index = try std.fmt.parseInt(u16, index_str, 10);
            break :is_index_changed name_index != old_name_index;
        } else false;

        if (!is_target and !is_changed and !is_index_changed) {
            name_index += 1;
            continue;
        }

        var new_index_buf: [32]u8 = undefined;
        var new_index: []const u8 = if (is_index_changed) try http.tprint("{d}", .{ name_index }) else index_str;
        var is_placeholder = true;

        if (index_str.len > 0) {
            if (data.future.len == 0) {
                if (is_target) {
                    _ = try req.response();
                } else {
                    try req.render("common/post_additional_name.zk", .{
                        .index = index_str,
                        .swap_oob = "delete",
                    }, .{});
                }
                continue;
            }
            name_index += 1;
            is_placeholder = false;
        } else if (data.future.len > 0 and data.valid) {
            if (options.rnd) |rnd| {
                var buf: [16]u8 = undefined;
                rnd.fill(&buf);
                const Base64 = std.base64.url_safe_no_pad.Encoder;
                new_index = Base64.encode(&new_index_buf, &buf);
            } else {
                new_index = try std.fmt.bufPrint(&new_index_buf, "{d}", .{ txn.additional_names.count() - 1 });
            }
            is_placeholder = false;
        }

        const render_data = .{
            .saved = changes_applied and is_changed,
            .valid = data.valid,
            .err = data.err,
            .post_prefix = options.post_prefix,
            .index = if (is_placeholder) null else new_index,
            .swap_oob = if (is_target) null else try http.tprint("outerHTML:#additional_name{s}", .{ index_str }),
            .name = data.future,
        };

        if (is_placeholder) {
            try req.render("common/post_additional_name_placeholder.zk", render_data, .{});
        } else {
            try req.render("common/post_additional_name.zk", render_data, .{});
            if (index_str.len == 0) {
                try req.render("common/post_additional_name_placeholder.zk", .{
                    .post_prefix = options.post_prefix,
                }, .{});
            }
        }
    }
}

const log = std.log.scoped(.http);

const Field_Data = @import("Field_Data.zig");
const http = @import("http");
const std = @import("std");
