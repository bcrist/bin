pub fn get(session: ?Session, req: *http.Request, db: *DB) !void {
    var txn = Transaction.init_empty(db);
    try txn.process_query_params(req);
    try txn.validate();
    try txn.render_results(session, req, .{
        .target = .add,
        .rnd = null,
    });
}

pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
    var txn = Transaction.init_empty(db);
    try txn.process_form_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    if (!txn.changes_applied) {
        log.warn("Could not add part; parameters not valid", .{});
        return error.BadRequest;
    }
    try txn.render_results(session, req, .{
        .target = .add,
        .rnd = null,
    });
}

pub const validate = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *const DB) !void {
        var txn = Transaction.init_empty(db);
        try txn.process_form_params(req);
        try txn.validate();

        var path_iter = req.path_iterator();
        _ = path_iter.next(); // /p
        const target_str = path_iter.next() orelse return error.BadRequest;
        if (std.mem.eql(u8, target_str, "add")) {
            try req.render("common/add_cancel.zk", .{
                .valid = txn.valid,
                .cancel_url = "/p",
            }, .{});
        } else if (std.mem.eql(u8, target_str, "parent_mfr")) {
            try txn.render_results(session, req, .{
                .target = .parent_mfr,
                .rnd = null,
            });
        } else if (std.mem.eql(u8, target_str, "pkg_mfr")) {
            try txn.render_results(session, req, .{
                .target = .pkg_mfr,
                .rnd = null,
            });
        } else {
            const field = std.meta.stringToEnum(Transaction.Field, target_str) orelse return error.BadRequest;
            try txn.render_results(session, req, .{
                .target = .{ .field = field },
                .rnd = null,
            });
        }
    }
};

pub const validate_dist_pn = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *const DB, rnd: *std.rand.Xoshiro256) !void {
        var txn = Transaction.init_empty(db);
        try txn.process_form_params(req);
        try txn.validate();
        try txn.render_results(session, req, .{
            .target = .{
                .dist_pn = try req.get_path_param("dist_pn") orelse "",
            },
            .rnd = rnd,
        });
    }
};

const log = std.log.scoped(.http);

const Transaction = @import("Transaction.zig");
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
