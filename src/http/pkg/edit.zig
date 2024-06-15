pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
    const requested_pkg_name = try req.get_path_param("pkg");
    const idx = Package.maybe_lookup(db, requested_pkg_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /pkg:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;

    var txn = try Transaction.init_idx(db, idx);
    try txn.process_all_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    try txn.render_results(session, req, .{
        .target = .{ .field = field },
        .post_prefix = try http.tprint("/pkg:{}", .{ http.fmtForUrl(Package.get_id(db, idx)) }),
        .rnd = null,
    });
}

pub const additional_name = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
        const idx = Package.maybe_lookup(db, try req.get_path_param("pkg")) orelse return;
        var txn = try Transaction.init_idx(db, idx);
        try txn.process_all_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(session, req, .{
            .target = .{
                .additional_name = try req.get_path_param("additional_name") orelse "",
            },
            .post_prefix = try http.tprint("/pkg:{}", .{ http.fmtForUrl(Package.get_id(db, idx)) }),
            .rnd = null,
        });
    }
};


const Transaction = @import("Transaction.zig");
const Package = DB.Package;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
