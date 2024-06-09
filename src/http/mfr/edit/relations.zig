pub fn post(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;
    const mfr_id = Manufacturer.get_id(db, idx);
    const relation_list = try get_sorted_relations(db, idx);
    const post_prefix = try http.tprint("/mfr:{}", .{ http.fmtForUrl(mfr_id) });

    var new_list = try std.ArrayList(Relation).initCapacity(http.temp(), relation_list.items.len);
    var apply_changes = true;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const expected_prefix = "relation";
        if (!std.mem.startsWith(u8, param.name, expected_prefix)) continue;
        const index_str = param.name[expected_prefix.len..];
        if (index_str.len == 0 or index_str[0] == '_') continue;
        const index = std.fmt.parseUnsigned(usize, index_str, 10) catch {
            log.warn("Invalid index: {s}", .{ index_str });
            apply_changes = false;
            continue;
        };
        if (index >= relation_list.items.len) {
            log.warn("Index {} >= relation list size {}", .{ index, relation_list.items.len });
            apply_changes = false;
        }

        try new_list.append(relation_list.items[index]);
    }

    if (relation_list.items.len != new_list.items.len) {
        log.warn("Expected {} relations; found {}", .{ relation_list.items.len, new_list.items.len });
        apply_changes = false;
    }

    if (apply_changes) {
        for (0.., new_list.items) |i, relation| {
            log.debug("Setting {} {} order index to {}", .{ idx, relation.db_index.?, i });
            try Manufacturer.Relation.set_order_index(db, idx, relation.db_index.?, @intCast(i));
        }
    }

    for (0.., new_list.items) |i, relation| {
        try req.render("mfr/post_relation.zk", .{
            .valid = true,
            .post_prefix = post_prefix,
            .index = i,
            .kind = relation.kind,
            .kind_str = relation.kind_str,
            .other = relation.other,
            .year = relation.year,
        }, .{});
    }
    try req.render("mfr/post_relation_placeholder.zk", .{ .post_prefix = post_prefix }, .{});
}

const log = std.log.scoped(.@"http.mfr");

const Relation = @import("../../mfr.zig").Relation;
const get_sorted_relations = @import("../../mfr.zig").get_sorted_relations;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
