pub fn post(session: ?Session, req: *http.Request, db: *DB, tz: ?*const tempora.Timezone) !void {
    const requested_order_name = try req.get_path_param("o");
    const idx = Order.maybe_lookup(db, requested_order_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /o:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;

    var txn = try Transaction.init_idx(db, idx, tz);
    try txn.process_form_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    try txn.render_results(session, req, .{
        .target = .{ .field = field },
        .rnd = null,
    });
}

pub const prj = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *DB, tz: ?*const tempora.Timezone) !void {
        const requested_order_name = try req.get_path_param("o");
        const idx = Order.maybe_lookup(db, requested_order_name) orelse return;
        var txn = try Transaction.init_idx(db, idx, tz);
        try txn.process_form_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(session, req, .{
            .target = .{
                .project = try req.get_path_param("prj") orelse "",
            },
            .rnd = null,
        });
    }
};

const Transaction = @import("Transaction.zig");
const Order = DB.Order;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
