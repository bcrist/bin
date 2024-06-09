pub fn post(req: *http.Request, db: *DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /pkg:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;

    var txn: Transaction = .{
        .db = db,
        .idx = idx,
    };

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        try txn.process_param(param);
    }

    try txn.validate();
    try txn.apply_changes(db);

    if (txn.valid) if (txn.id) |id| {
        try req.see_other(try http.tprint("/pkg:{}?edit", .{ http.fmtForUrl(id) }));
        return;
    };

    const pkg = Package.get(db, idx);
    const post_prefix = try http.tprint("/pkg:{}", .{ http.fmtForUrl(pkg.id) });

    const render_data = .{
        .validating = true,
        .valid = txn.valid,
        .saved = txn.valid,
        .err = txn.err,
        .obj = pkg,
        .parent_id = txn.parent orelse if (pkg.parent) |parent| Package.get_id(db, parent) else null,
        .mfr_id = txn.mfr orelse if (pkg.manufacturer) |mfr| Manufacturer.get_id(db, mfr) else null,
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

const log = std.log.scoped(.@"http.pkg");

const Transaction = @import("Transaction.zig");
const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
