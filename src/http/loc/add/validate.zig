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
    
    var txn: Transaction = .{
        .db = db,
        .idx = null,
    };

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            was_valid = false;
            continue;
        }
        try txn.process_param(param);
    }

    try txn.validate();

    if (mode != .add and was_valid != txn.valid) {
        try req.add_response_header("hx-trigger", "revalidate");
    }

    var loc = Location.init_empty(txn.id orelse "", 0);
    loc.full_name = txn.full_name;
    loc.notes = txn.notes;

    const render_data = .{
        .validating = true,
        .valid = txn.valid,
        .err = txn.err,
        .obj = loc,
        .parent_id = txn.parent,
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

const Transaction = @import("../Transaction.zig");
const Location = DB.Location;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
