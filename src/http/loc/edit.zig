pub fn post(req: *http.Request, db: *DB) !void {
    const requested_loc_name = try req.get_path_param("loc");
    const idx = Location.maybe_lookup(db, requested_loc_name) orelse return;
    var loc = db.locs.get(@intFromEnum(idx));
    const post_prefix = try http.tprint("/loc:{}", .{ http.percent_encoding.fmtEncoded(loc.id) });

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /loc:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Field, field_str) orelse return error.BadRequest;

    var valid = true;
    var message: []const u8 = "";
    var parent_id: ?[]const u8 = null;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const str_value = try http.temp().dupe(u8, param.value orelse "");
        if (!std.mem.eql(u8, param.name, field_str)) continue;
        switch (field) {
            .id => {
                loc.id = (try validate_name(str_value, db, idx, .id, &valid, &message)).?;
                if (valid and try Location.set_id(db, idx, loc.id)) {
                    try req.add_response_header("HX-Location", try http.tprint("/loc:{}?edit", .{ http.percent_encoding.fmtEncoded(loc.id) }));
                }
            },
            .full_name => {
                loc.full_name = try validate_name(str_value, db, idx, .full_name, &valid, &message);
                if (valid) {
                    try Location.set_full_name(db, idx, loc.full_name);
                }
            },
            .notes => {
                loc.notes = if (str_value.len > 0) str_value else null;
                try Location.set_notes(db, idx, loc.notes);
            },
            .parent => {
                if (str_value.len > 0) {
                    const parent_idx = Location.maybe_lookup(db, str_value) orelse {
                        log.debug("Invalid parent location: {s}", .{ str_value });
                        valid = false;
                        message = "invalid location";
                        continue;
                    };
                    if (Location.is_ancestor(db, parent_idx, idx)) {
                        log.debug("Recursive location parent chain involving: {s}", .{ str_value });
                        valid = false;
                        message = "Recursive locations are not allowed!";
                        parent_id = loc.id;
                        continue;
                    }

                    try Location.set_parent(db, idx, parent_idx);
                    parent_id = db.locs.items(.id)[@intFromEnum(parent_idx)];
                } else {
                    try Location.set_parent(db, idx, null);
                }
            },
        }
        break;
    }

    const render_data = .{
        .validating = true,
        .valid = valid,
        .saved = valid,
        .err = message,
        .loc = loc,
        .parent_id = parent_id,
        .post_prefix = post_prefix,
    };

    switch (field) {
        .id => try req.render("loc/post_id.zk", render_data, .{}),
        .full_name => try req.render("loc/post_full_name.zk", render_data, .{}),
        .notes => try req.render("loc/post_notes.zk", render_data, .{}),
        .parent => try req.render("loc/post_parent.zk", render_data, .{}),
    }
}

const log = std.log.scoped(.@"http.loc");

const Field = @import("../loc.zig").Field;
const validate_name = @import("../loc.zig").validate_name;

const Location = DB.Location;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
