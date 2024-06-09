const Validate_Mode = enum {
    add,
    id,
    full_name,
    notes,
    parent,
    mfr,
};

pub fn post(req: *http.Request, db: *const DB) !void {
    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /pkg
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

    var pkg = Package.init_empty(txn.id orelse "", 0);
    pkg.full_name = txn.full_name;
    pkg.notes = txn.notes;

    const render_data = .{
        .validating = true,
        .valid = txn.valid,
        .err = txn.err,
        .obj = pkg,
        .parent_id = txn.parent,
        .mfr_id = txn.mfr,
        .parent_search_url = "/pkg",
        .post_prefix = "/pkg",
        .cancel_url = "/pkg",
    };

    switch (mode) {
        .add => try req.render("common/add_cancel.zk", render_data, .{}),
        .id => try req.render("common/post_id.zk", render_data, .{}),
        .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
        .notes => try req.render("common/post_notes.zk", render_data, .{}),
        .parent => try req.render("common/post_parent.zk", render_data, .{}),
        .mfr => try req.render("common/post_mfr.zk", render_data, .{}),
    }
}

const log = std.log.scoped(.@"http.pkg");

const Transaction = @import("../Transaction.zig");
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
