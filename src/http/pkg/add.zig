pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    try Session.redirect_if_missing(req, session);
    var txn = Transaction.init_empty(db);

    if (try req.get_path_param("pkg")) |id| {
        try txn.process_param(.{ .name = "id", .value = id });
    }

    var iter = req.query_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "edit")) continue;
        try txn.process_param(param);
    }

    try txn.validate();
    try txn.render_results(session, req, .{
        .target = .add,
        .post_prefix = "/pkg",
        .rnd = null,
    });
}

pub fn post(req: *http.Request, db: *DB) !void {
    var another = false;
    var txn = Transaction.init_empty(db);
    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "another")) {
            another = true;
            continue;
        }
        try txn.process_param(param);
    }
    try txn.validate();
    try txn.apply_changes(db);

    if (!txn.changes_applied) {
        log.warn("Could not add package; parameters not valid", .{});
        return error.BadRequest;
    } else if (another) {
        try req.see_other(try http.tprint("/pkg/add{s}", .{ req.hx_current_query() }));
    } else {
        try req.see_other(try http.tprint("/pkg:{}", .{ http.fmtForUrl(txn.fields.id.future) }));
    }
}

pub const validate = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *const DB) !void {
        var txn = Transaction.init_empty(db);
        try txn.process_all_params(req);
        try txn.validate();

        var path_iter = req.path_iterator();
        _ = path_iter.next(); // /pkg
        const target_str = path_iter.next() orelse return error.BadRequest;
        if (std.mem.eql(u8, target_str, "add")) {
            try req.render("common/add_cancel.zk", .{
                .valid = txn.valid,
                .cancel_url = "/pkg",
            }, .{});
        } else {
            const field = std.meta.stringToEnum(Transaction.Field, target_str) orelse return error.BadRequest;
            try txn.render_results(session, req, .{
                .target = .{ .field = field },
                .post_prefix = "/pkg",
                .rnd = null,
            });
        }
    }
};

const log = std.log.scoped(.http);

const Transaction = @import("Transaction.zig");
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");
