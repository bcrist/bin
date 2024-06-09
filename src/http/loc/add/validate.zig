const Validate_Mode = enum {
    add,
    id,
    full_name,
    notes,
    parent,
};

pub fn post(req: *http.Request, db: *const DB) !void {
    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /loc
    const mode_str = path_iter.next() orelse return error.BadRequest;
    const mode = std.meta.stringToEnum(Validate_Mode, mode_str) orelse return error.BadRequest;

    var was_valid = true;
    var valid = true;
    var message: []const u8 = "";
    var loc = Location.init_empty("", 0);
    var parent_id: ?[]const u8 = null;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            was_valid = false;
            continue;
        }
        const str_value = try http.temp().dupe(u8, param.value orelse "");
        const field = std.meta.stringToEnum(Validate_Mode, param.name) orelse return error.BadRequest;
        switch (field) {
            .add => return error.BadRequest,
            .id => loc.id = try validate_name(str_value, db, null, .id, &valid, &message) orelse "",
            .full_name => loc.full_name = try validate_name(str_value, db, null, .full_name, &valid, &message),
            .notes => loc.notes = if (str_value.len > 0) str_value else null,
            .parent => if (str_value.len > 0) {
                const parent_idx = Location.maybe_lookup(db, str_value) orelse {
                    log.debug("Invalid parent location: {s}", .{ str_value });
                    valid = false;
                    message = "invalid location";
                    continue;
                };
                parent_id = Location.get_id(db, parent_idx);
            },
        }
    }

    if (mode != .add and was_valid != valid) {
        try req.add_response_header("hx-trigger", "revalidate");
    }

    const render_data = .{
        .validating = true,
        .valid = valid,
        .err = message,
        .obj = loc,
        .parent_id = parent_id,
        .parent_search_url = "/loc",
        .post_prefix = "/loc",
        .cancel_url = "/loc",
    };

    switch (mode) {
        .add => try req.render("common/add_cancel.zk", render_data, .{}),
        .id => try req.render("common/post_id.zk", render_data, .{}),
        .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
        .notes => try req.render("common/post_notes.zk", render_data, .{}),
        .parent => try req.render("common/post_parent.zk", render_data, .{}),
    }
}

const log = std.log.scoped(.@"http.loc");

const validate_name = @import("../../loc.zig").validate_name;

const Location = DB.Location;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
