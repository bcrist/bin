pub fn post(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /mfr:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;    

    var txn = try Transaction.init_idx(db, idx);
    try txn.process_all_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    try txn.render_results(req, .{
        .target = .{ .field = field },
        .post_prefix = try http.tprint("/mfr:{}", .{ http.fmtForUrl(Manufacturer.get_id(db, idx)) }),
        .rnd = null,
    });
}

pub const additional_name = struct {
    pub fn post(req: *http.Request, db: *DB) !void {
        const idx = Manufacturer.maybe_lookup(db, try req.get_path_param("mfr")) orelse return;
        var txn = try Transaction.init_idx(db, idx);
        try txn.process_all_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(req, .{
            .target = .{
                .additional_name = try req.get_path_param("additional_name") orelse "",
            },
            .post_prefix = try http.tprint("/mfr:{}", .{ http.fmtForUrl(Manufacturer.get_id(db, idx)) }),
            .rnd = null,
        });
    }
};

pub const relation = struct {
    pub fn post(req: *http.Request, db: *DB) !void {
        const idx = Manufacturer.maybe_lookup(db, try req.get_path_param("mfr")) orelse return;
        var txn = try Transaction.init_idx(db, idx);
        try txn.process_all_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(req, .{
            .target = .{
                .relation = try req.get_path_param("relation") orelse "",
            },
            .post_prefix = try http.tprint("/mfr:{}", .{ http.fmtForUrl(Manufacturer.get_id(db, idx)) }),
            .rnd = null,
        });
    }
};

const log = std.log.scoped(.@"http.mfr");

const Transaction = @import("Transaction.zig");
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const http = @import("http");
const std = @import("std");
