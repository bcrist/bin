pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone) !void {
    const id = (try req.get_path_param("mfr")) orelse "";
    const now = std.time.milliTimestamp();
    const mfr = Manufacturer.init_empty(id, now);
    try render(mfr, .{
        .session = session,
        .req = req,
        .tz = tz,
        .relations = &.{},
        .packages = &.{},
        .mode = .add,
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
        log.warn("Could not add mfr; parameters not valid", .{});
        return error.BadRequest;
    } else if (another) {
        try req.see_other(try http.tprint("/mfr/add{s}", .{ req.hx_current_query() }));
    } else {
        try req.see_other(try http.tprint("/mfr:{}", .{ http.fmtForUrl(txn.fields.id.future) }));
    }
}

pub const validate = struct {
    pub fn post(req: *http.Request, db: *const DB) !void {
        var txn = Transaction.init_empty(db);
        try txn.process_all_params(req);
        try txn.validate();

        var path_iter = req.path_iterator();
        _ = path_iter.next(); // /mfr
        const target_str = path_iter.next() orelse return error.BadRequest;
        if (std.mem.eql(u8, target_str, "add")) {
            try req.render("common/add_cancel.zk", .{
                .valid = txn.valid,
                .cancel_url = "/mfr",
            }, .{});
        } else {
            const field = std.meta.stringToEnum(Transaction.Field, target_str) orelse return error.BadRequest;
            try txn.render_results(req, .{
                .target = .{ .field = field },
                .post_prefix = "/mfr",
                .rnd = null,
            });
        }
    }
};

pub const validate_additional_name = struct {
    pub fn post(req: *http.Request, db: *const DB, rnd: *std.rand.Xoshiro256) !void {
        var txn = Transaction.init_empty(db);
        try txn.process_all_params(req);
        try txn.validate();

        try txn.render_results(req, .{
            .target = .{
                .additional_name = try req.get_path_param("additional_name") orelse "",
            },
            .post_prefix = "/mfr",
            .rnd = rnd,
        });
    }
};

pub const validate_relation = struct {
    pub fn post(req: *http.Request, db: *const DB, rnd: *std.rand.Xoshiro256) !void {
        var txn = Transaction.init_empty(db);
        try txn.process_all_params(req);
        try txn.validate();

        try txn.render_results(req, .{
            .target = .{
                .relation = try req.get_path_param("relation") orelse "",
            },
            .post_prefix = "/mfr",
            .rnd = rnd,
        });
    }
};


const log = std.log.scoped(.@"http.mfr");

const render = @import("../mfr.zig").render;

const Transaction = @import("Transaction.zig");
const Relation = Manufacturer.Relation;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
