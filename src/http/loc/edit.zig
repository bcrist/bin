pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
    const requested_loc_name = try req.get_path_param("loc");
    const idx = Location.maybe_lookup(db, requested_loc_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /loc:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;

    var txn = try Transaction.init_idx(db, idx);
    try txn.process_all_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    try txn.render_results(session, req, .{
        .target = .{ .field = field },
        .post_prefix = try http.tprint("/loc:{}", .{ http.fmtForUrl(Location.get_id(db, idx)) }),
        .rnd = null,
    });
}

const log = std.log.scoped(.@"http.loc");

const Transaction = @import("Transaction.zig");
const Location = DB.Location;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
