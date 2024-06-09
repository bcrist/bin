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
    var valid = true;
    var message: []const u8 = "";
    var pkg = Package.init_empty("", 0);
    var parent_id: ?[]const u8 = null;
    var mfr_id: ?[]const u8 = null;

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
            .id => pkg.id = try validate_name(str_value, db, null, .id, &valid, &message) orelse "",
            .full_name => pkg.full_name = try validate_name(str_value, db, null, .full_name, &valid, &message),
            .notes => pkg.notes = if (str_value.len > 0) str_value else null,
            .parent => if (str_value.len > 0) {
                const parent_idx = Package.maybe_lookup(db, str_value) orelse {
                    log.debug("Invalid parent package: {s}", .{ str_value });
                    valid = false;
                    message = "invalid package";
                    continue;
                };
                parent_id = Package.get_id(db, parent_idx);
            },
            .mfr => if (str_value.len > 0) {
                const mfr_idx = Manufacturer.maybe_lookup(db, str_value) orelse {
                    log.debug("Invalid manufacturer: {s}", .{ str_value });
                    valid = false;
                    message = "invalid manufacturer";
                    continue;
                };
                mfr_id = Manufacturer.get_id(db, mfr_idx);
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
        .obj = pkg,
        .parent_id = parent_id,
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

const validate_name = @import("../../pkg.zig").validate_name;

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
