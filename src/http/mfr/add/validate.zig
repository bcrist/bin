const Validate_Mode = enum {
    add,
    id,
    full_name,
    country,
    founded_year,
    suspended_year,
    notes,
    website,
    wiki,
};

pub fn post(req: *http.Request, db: *const DB) !void {
    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /mfr
    const mode_str = path_iter.next() orelse return error.BadRequest;
    const mode = std.meta.stringToEnum(Validate_Mode, mode_str) orelse return error.BadRequest;

    var was_valid = true;
    var valid = true;
    var message: []const u8 = "";
    var mfr = Manufacturer.init_empty("", 0);

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        if (std.mem.eql(u8, param.name, "invalid")) {
            was_valid = false;
            continue;
        }
        const str_value = try http.temp().dupe(u8, param.value orelse "");

        if (std.mem.startsWith(u8, param.name, "additional_name")) {
            const index_str = param.name["additional_name".len..];
            if (index_str.len > 0 or str_value.len > 0) {
                _ = try validate_name(str_value, db, null, .{ .additional_name = null }, &valid, &message);
            }
            continue;
        }

        if (std.mem.startsWith(u8, param.name, "relation_kind")) {
            continue;
        }

        if (std.mem.startsWith(u8, param.name, "relation_other")) {
            const index_str = param.name["relation_other".len..];
            if (index_str.len > 0 or str_value.len > 0) {
                _ = Manufacturer.maybe_lookup(db, str_value) orelse {
                    log.debug("Invalid mfr relation: {s}", .{ str_value });
                    valid = false;
                    message = "invalid relation manufacturer";
                };
            }
            continue;
        }

        if (std.mem.startsWith(u8, param.name, "relation_year")) {
            const index_str = param.name["relation_year".len..];
            if (index_str.len > 0 or str_value.len > 0) {
                _ = try validate_year(str_value, &valid, &message);
            }
            continue;
        }

        const field = std.meta.stringToEnum(Validate_Mode, param.name) orelse return error.BadRequest;
        switch (field) {
            .add => return error.BadRequest,
            .id => mfr.id = try validate_name(str_value, db, null, .id, &valid, &message) orelse "",
            .full_name => mfr.full_name = try validate_name(str_value, db, null, .full_name, &valid, &message),
            .country => mfr.country = if (str_value.len > 0) str_value else null,
            .founded_year => mfr.founded_year = try validate_year(str_value, &valid, &message),
            .suspended_year => mfr.suspended_year = try validate_year(str_value, &valid, &message),
            .notes => mfr.notes = if (str_value.len > 0) str_value else null,
            .website => mfr.website = if (str_value.len > 0) str_value else null,
            .wiki => mfr.wiki = if (str_value.len > 0) str_value else null,
        }
    }

    if (mode != .add and was_valid != valid) {
        try req.add_response_header("hx-trigger", "revalidate");
    }

    const render_data = .{
        .validating = true,
        .valid = valid,
        .err = message,
        .mfr = mfr,
        .post_prefix = "/mfr",
    };

    switch (mode) {
        .add => try req.render("_add_button.zk", render_data, .{}),
        .id => try req.render("mfr/post_id.zk", render_data, .{}),
        .full_name => try req.render("mfr/post_full_name.zk", render_data, .{}),
        .country => try req.render("mfr/post_country.zk", render_data, .{}),
        .founded_year => try req.render("mfr/post_founded_year.zk", render_data, .{}),
        .suspended_year => try req.render("mfr/post_suspended_year.zk", render_data, .{}),
        .notes => try req.render("mfr/post_notes.zk", render_data, .{}),
        .website => try req.render("mfr/post_website.zk", render_data, .{}),
        .wiki => try req.render("mfr/post_wiki.zk", render_data, .{}),
    }
}

const log = std.log.scoped(.@"http.mfr");

const validate_name = @import("../../mfr.zig").validate_name;
const validate_year = @import("../../mfr.zig").validate_year;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../../DB.zig");
const Session = @import("../../../Session.zig");
const sort = @import("../../../sort.zig");
const slimselect = @import("../../slimselect.zig");
const http = @import("http");
const std = @import("std");
