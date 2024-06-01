pub const validate = @import("add/validate.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone) !void {
    const id = (try req.get_path_param("loc")) orelse "";
    const now = std.time.milliTimestamp();
    const loc = Location.init_empty(id, now);
    try render(session, req, tz, loc, null, .add);
}

pub fn post(req: *http.Request, db: *DB) !void {
    const alloc = http.temp();

    var loc = Location.init_empty("", std.time.milliTimestamp());

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            log.warn("Found 'invalid' param in request body!", .{});
            return error.BadRequest;
        }

        const value = param.value orelse "";

        const field = std.meta.stringToEnum(Field, param.name) orelse {
            log.warn("Unrecognized parameter: {s}", .{ param.name });
            return error.BadRequest;
        };
        const copied_value = try alloc.dupe(u8, value);
        var valid = true;
        var message: []const u8 = "";
        switch (field) {
            .id => loc.id = try validate_name(copied_value, db, null, .id, &valid, &message) orelse "",
            .full_name => loc.full_name = try validate_name(copied_value, db, null, .full_name, &valid, &message),
            .notes => loc.notes = if (copied_value.len > 0) copied_value else null,
            .parent => {
                if (copied_value.len == 0) {
                    loc.parent = null;
                } else if (Location.maybe_lookup(db, copied_value)) |idx| {
                    loc.parent = idx;
                } else {
                    log.warn("Invalid parent location {s}", .{ copied_value });
                    return error.BadRequest;
                }
            },
        }
        if (!valid) {
            log.warn("Invalid {s} parameter: {s} ({s})", .{ param.name, copied_value, message });
            return error.BadRequest;
        }
    }

    if (loc.full_name) |full_name| {
        if (std.mem.eql(u8, loc.id, full_name)) {
            loc.full_name = null;
        }
    }

    const idx = try Location.lookup_or_create(db, loc.id);
    try Location.set_parent(db, idx, loc.parent);
    try Location.set_full_name(db, idx, loc.full_name);
    try Location.set_notes(db, idx, loc.notes);

    if (req.get_header("hx-request")) |_| {
        try req.add_response_header("hx-location", try http.tprint("/loc:{}", .{ http.percent_encoding.fmtEncoded(loc.id) }));
        req.response_status = .no_content;
        try req.respond("");
    } else {
        try req.add_response_header("location", try http.tprint("/loc:{}", .{ http.percent_encoding.fmtEncoded(loc.id) }));
        req.response_status = .see_other;
        try req.respond("");
    }
}

const log = std.log.scoped(.@"http.loc");

const Field = @import("../loc.zig").Field;
const render = @import("../loc.zig").render;
const validate_name = @import("../loc.zig").validate_name;

const Location = DB.Location;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
