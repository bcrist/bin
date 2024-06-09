pub const validate = @import("add/validate.zig");

pub fn get(session: ?Session, req: *http.Request, tz: ?*const tempora.Timezone) !void {
    const id = (try req.get_path_param("mfr")) orelse "";
    const now = std.time.milliTimestamp();
    const pkg = Package.init_empty(id, now);
    try render(session, req, tz, pkg, null, &.{}, null, .add);
}

pub fn post(req: *http.Request, db: *DB) !void {
    const alloc = http.temp();

    var pkg = Package.init_empty("", std.time.milliTimestamp());

    var another = false;

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            log.warn("Found 'invalid' param in request body!", .{});
            return error.BadRequest;
        }

        if (std.mem.eql(u8, param.name, "another")) {
            another = true;
            continue;
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
            .id => pkg.id = try validate_name(copied_value, db, null, .id, &valid, &message) orelse "",
            .full_name => pkg.full_name = try validate_name(copied_value, db, null, .full_name, &valid, &message),
            .notes => pkg.notes = if (copied_value.len > 0) copied_value else null,
            .parent => {
                if (copied_value.len == 0) {
                    pkg.parent = null;
                } else if (Package.maybe_lookup(db, copied_value)) |idx| {
                    pkg.parent = idx;
                } else {
                    log.warn("Invalid parent package {s}", .{ copied_value });
                    return error.BadRequest;
                }
            },
            .mfr => {
                if (copied_value.len == 0) {
                } else if (Manufacturer.maybe_lookup(db, copied_value)) |idx| {
                    pkg.manufacturer = idx;
                } else {
                    log.warn("Invalid manufacturer {s}", .{ copied_value });
                    return error.BadRequest;
                }
            },
        }
        if (!valid) {
            log.warn("Invalid {s} parameter: {s} ({s})", .{ param.name, copied_value, message });
            return error.BadRequest;
        }
    }

    if (pkg.full_name) |full_name| {
        if (std.mem.eql(u8, pkg.id, full_name)) {
            pkg.full_name = null;
        }
    }

    const idx = try Package.lookup_or_create(db, pkg.id);
    try Package.set_parent(db, idx, pkg.parent);
    try Package.set_mfr(db, idx, pkg.manufacturer);
    try Package.set_full_name(db, idx, pkg.full_name);
    try Package.set_notes(db, idx, pkg.notes);

    try req.see_other(if (another) "/pkg/add" else try http.tprint("/pkg:{}", .{ http.percent_encoding.fmtEncoded(pkg.id) }));
}

const log = std.log.scoped(.@"http.pkg");

const Field = @import("../pkg.zig").Field;
const render = @import("../pkg.zig").render;
const validate_name = @import("../pkg.zig").validate_name;

const Package = DB.Package;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
