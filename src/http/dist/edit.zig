pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
    const requested_dist_name = try req.get_path_param("dist");
    const idx = Distributor.maybe_lookup(db, requested_dist_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /dist:*
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

pub const additional_name = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
        const idx = Distributor.maybe_lookup(db, try req.get_path_param("dist")) orelse return;
        var txn = try Transaction.init_idx(db, idx);
        try txn.process_form_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(session, req, .{
            .target = .{
                .additional_name = try req.get_path_param("additional_name") orelse "",
            },
            .rnd = null,
        });
    }
};

pub const relation = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
        const idx = Distributor.maybe_lookup(db, try req.get_path_param("dist")) orelse return;
        var txn = try Transaction.init_idx(db, idx);
        try txn.process_form_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(session, req, .{
            .target = .{
                .relation = try req.get_path_param("relation") orelse "",
            },
            .rnd = null,
        });
    }
};

const Transaction = @import("Transaction.zig");
const Distributor = DB.Distributor;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
