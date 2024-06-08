pub fn post(req: *http.Request, db: *DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse return;
    var pkg = db.pkgs.get(@intFromEnum(idx));
    const post_prefix = try http.tprint("/pkg:{}", .{ http.percent_encoding.fmtEncoded(pkg.id) });

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /pkg:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Field, field_str) orelse return error.BadRequest;

    var valid = true;
    var message: []const u8 = "";
    var parent_id: ?[]const u8 = null;
    var mfr_id: ?[]const u8 = null;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const str_value = try http.temp().dupe(u8, param.value orelse "");
        if (!std.mem.eql(u8, param.name, field_str)) continue;
        switch (field) {
            .id => {
                pkg.id = (try validate_name(str_value, db, idx, .id, &valid, &message)).?;
                if (valid and try Package.set_id(db, idx, pkg.id)) {
                    try req.add_response_header("HX-Location", try http.tprint("/pkg:{}?edit", .{ http.percent_encoding.fmtEncoded(pkg.id) }));
                }
            },
            .full_name => {
                pkg.full_name = try validate_name(str_value, db, idx, .full_name, &valid, &message);
                if (valid) {
                    try Package.set_full_name(db, idx, pkg.full_name);
                }
            },
            .notes => {
                pkg.notes = if (str_value.len > 0) str_value else null;
                try Package.set_notes(db, idx, pkg.notes);
            },
            .parent => {
                if (str_value.len > 0) {
                    const parent_idx = Package.maybe_lookup(db, str_value) orelse {
                        log.debug("Invalid parent package: {s}", .{ str_value });
                        valid = false;
                        message = "invalid package";
                        continue;
                    };
                    if (Package.is_ancestor(db, parent_idx, idx)) {
                        log.debug("Recursive package parent chain involving: {s}", .{ str_value });
                        valid = false;
                        message = "Recursive packages are not allowed!";
                        parent_id = str_value;
                        continue;
                    }

                    try Package.set_parent(db, idx, parent_idx);
                    parent_id = db.pkgs.items(.id)[@intFromEnum(parent_idx)];
                } else {
                    try Package.set_parent(db, idx, null);
                }
            },
            .mfr => {
                if (str_value.len > 0) {
                    const mfr_idx = Manufacturer.maybe_lookup(db, str_value) orelse {
                        log.debug("Invalid manufacturer: {s}", .{ str_value });
                        valid = false;
                        message = "invalid manufacturer";
                        continue;
                    };

                    try Package.set_mfr(db, idx, mfr_idx);
                    mfr_id = db.mfrs.items(.id)[@intFromEnum(mfr_idx)];
                } else {
                    try Package.set_mfr(db, idx, null);
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
        .obj = pkg,
        .parent_id = parent_id,
        .mfr_id = mfr_id,
        .parent_search_url = "/pkg",
        .post_prefix = post_prefix,
    };

    switch (field) {
        .id => try req.render("common/post_id.zk", render_data, .{}),
        .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
        .notes => try req.render("common/post_notes.zk", render_data, .{}),
        .parent => try req.render("common/post_parent.zk", render_data, .{}),
        .mfr => try req.render("common/post_mfr.zk", render_data, .{}),
    }
}

const log = std.log.scoped(.@"http.loc");

const Field = @import("../pkg.zig").Field;
const validate_name = @import("../pkg.zig").validate_name;

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
