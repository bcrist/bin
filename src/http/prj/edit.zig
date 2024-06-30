pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
    const requested_prj_name = try req.get_path_param("prj");
    const idx = Project.maybe_lookup(db, requested_prj_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /prj:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;

    var txn = try Transaction.init_idx(db, idx);
    try txn.process_form_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    try txn.render_results(session, req, .{
        .target = .{ .field = field },
        .rnd = null,
    });
}

const Transaction = @import("Transaction.zig");
const Project = DB.Project;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
