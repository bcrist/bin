
pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
    const requested = try req.get_path_param("mfr");
    const idx = db.mfr_lookup.get(requested.?) orelse {
        try list.get(session, req, db);
        return;
    };
    const mfr = db.mfrs.get(@intFromEnum(idx));

    try req.render("mfr/info.zk", .{
        .mfr = mfr,
        .session = session,
        .full_name = mfr.full_name orelse mfr.id,
    }, .{});
}

pub const list = struct {
    pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
        const missing_mfr = try req.get_path_param("mfr");
        try req.render("mfr/list.zk", .{
            .mfr_list = db.mfrs.items(.id),
            .session = session,
            .missing_mfr = missing_mfr,
        }, .{});
    }
};

const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const Session = @import("../Session.zig");
const http = @import("http");
const std = @import("std");
