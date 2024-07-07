pub fn get(session: ?Session, req: *http.Request, db: *DB, tz: ?*const tempora.Timezone) !void {
    const DTO = tempora.Date_Time.With_Offset;
    const date = DTO.from_timestamp_s(std.time.timestamp(), tz).dt.date;
    var id_uniquifier: usize = 0;
    var id: []const u8 = "";
    while (id.len == 0) {
        id = try http.tprint("{YYMMDD}{d:0>2}", .{ date, id_uniquifier });
        id_uniquifier += 1;
        if (Order.maybe_lookup(db, id) != null) id = "";
    }

    var txn = Transaction.init_empty(db, tz);
    try txn.process_param(.{
        .name = "id",
        .value = id,
    });
    try txn.process_query_params(req);
    try txn.validate();
    try txn.render_results(session, req, .{
        .target = .add,
        .rnd = null,
    });
}

pub fn post(session: ?Session, req: *http.Request, db: *DB, tz: ?*const tempora.Timezone) !void {
    var txn = Transaction.init_empty(db, tz);
    try txn.process_form_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    if (!txn.changes_applied) {
        log.warn("Could not add order; parameters not valid", .{});
        return error.BadRequest;
    }
    try txn.render_results(session, req, .{
        .target = .add,
        .rnd = null,
    });
}

pub const validate = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *const DB, tz: ?*const tempora.Timezone) !void {
        var txn = Transaction.init_empty(db, tz);
        try txn.process_form_params(req);
        try txn.validate();

        var path_iter = req.path_iterator();
        _ = path_iter.next(); // /o
        const target_str = path_iter.next() orelse return error.BadRequest;
        if (std.mem.eql(u8, target_str, "add")) {
            try req.render("common/add_cancel.zk", .{
                .valid = txn.valid,
                .cancel_url = "/o",
            }, .{});
        } else {
            const field = std.meta.stringToEnum(Transaction.Field, target_str) orelse return error.BadRequest;
            try txn.render_results(session, req, .{
                .target = .{ .field = field },
                .rnd = null,
            });
        }
    }
};

pub const validate_prj = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *const DB, tz: ?*const tempora.Timezone, rnd: *std.rand.Xoshiro256) !void {
        var txn = Transaction.init_empty(db, tz);
        try txn.process_form_params(req);
        try txn.validate();
        try txn.render_results(session, req, .{
            .target = .{
                .project = try req.get_path_param("prj") orelse "",
            },
            .rnd = rnd,
        });
    }
};

const log = std.log.scoped(.http);

const Transaction = @import("Transaction.zig");
const Order = DB.Order;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
