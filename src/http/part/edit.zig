pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const requested_part_name = try req.get_path_param("p");
    const maybe_mfr_idx = Manufacturer.maybe_lookup(db, requested_mfr_name);
    const idx = Part.maybe_lookup(db, maybe_mfr_idx, requested_part_name) orelse return;

    var path_iter = req.path_iterator();
    if (requested_mfr_name != null) _ = path_iter.next(); // /mfr:*
    _ = path_iter.next(); // /p:*
    const field_str = path_iter.next() orelse return error.BadRequest;

    var txn = try Transaction.init_idx(db, idx);
    try txn.process_form_params(req);
    try txn.validate();
    try txn.apply_changes(db);
    if (std.mem.eql(u8, field_str, "parent_mfr")) {
        try txn.render_results(session, req, .{
            .target = .parent_mfr,
            .rnd = null,
        });
    } else {
        const field = std.meta.stringToEnum(Transaction.Field, field_str) orelse return error.BadRequest;
        try txn.render_results(session, req, .{
            .target = .{ .field = field },
            .rnd = null,
        });
    }
}

pub const dist_pn = struct {
    pub fn post(session: ?Session, req: *http.Request, db: *DB) !void {
        const requested_mfr_name = try req.get_path_param("mfr");
        const requested_part_name = try req.get_path_param("p");
        const maybe_mfr_idx = Manufacturer.maybe_lookup(db, requested_mfr_name);
        const idx = Part.maybe_lookup(db, maybe_mfr_idx, requested_part_name) orelse return;
        var txn = try Transaction.init_idx(db, idx);
        try txn.process_form_params(req);
        try txn.validate();
        try txn.apply_changes(db);
        try txn.render_results(session, req, .{
            .target = .{
                .dist_pn = try req.get_path_param("dist_pn") orelse "",
            },
            .rnd = null,
        });
    }
};

const Transaction = @import("Transaction.zig");
const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const http = @import("http");
const std = @import("std");