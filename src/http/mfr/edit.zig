pub const additional_name = @import("edit/additional_name.zig");
pub const additional_names = @import("edit/additional_names.zig");
pub const relation = @import("edit/relation.zig");
pub const relations = @import("edit/relations.zig");

const Field = enum {
    id,
    full_name,
    country,
    founded_year,
    suspended_year,
    notes,
    website,
    wiki,
};

pub fn post(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;
    var mfr = db.mfrs.get(@intFromEnum(idx));
    const post_prefix = try http.tprint("/mfr:{}", .{ http.percent_encoding.fmtEncoded(mfr.id) });

    var path_iter = req.path_iterator();
    _ = path_iter.next(); // /mfr:*
    const field_str = path_iter.next() orelse return error.BadRequest;
    const field = std.meta.stringToEnum(Field, field_str) orelse return error.BadRequest;

    var valid = true;
    var message: []const u8 = "";

    var iter = try req.form_iterator();
    while (try iter.next()) |param| {
        const str_value = param.value orelse "";
        if (!std.mem.eql(u8, param.name, field_str)) continue;
        switch (field) {
            .id => {
                mfr.id = try validate_name(str_value, db, idx, .id, &valid, &message);
                if (valid and try Manufacturer.set_id(db, idx, mfr.id)) {
                    try req.add_response_header("HX-Location", try http.tprint("/mfr:{}?edit", .{ http.percent_encoding.fmtEncoded(mfr.id) }));
                }
            },
            .full_name => {
                const full_name = try validate_name(str_value, db, idx, .full_name, &valid, &message);
                mfr.full_name = if (full_name.len == 0) null else full_name;
                if (valid) {
                    try Manufacturer.set_full_name(db, idx, mfr.full_name);
                }
            },
            .country => {
                mfr.country = str_value;
                if (valid) {
                    const maybe_country: ?[]const u8 = if (str_value.len == 0) null else str_value;
                    try Manufacturer.set_country(db, idx, maybe_country);
                }
            },
            .founded_year => {
                mfr.founded_year = try validate_year(str_value, &valid, &message);
                if (valid) {
                    try Manufacturer.set_founded_year(db, idx, mfr.founded_year);
                }
            },
            .suspended_year => {
                mfr.suspended_year = try validate_year(str_value, &valid, &message);
                if (valid) {
                    try Manufacturer.set_suspended_year(db, idx, mfr.suspended_year);
                }
            },
            .notes => {
                mfr.notes = str_value;
                if (valid) {
                    const maybe_str: ?[]const u8 = if (str_value.len == 0) null else str_value;
                    try Manufacturer.set_notes(db, idx, maybe_str);
                }
            },
            .website => {
                mfr.website = str_value;
                if (valid) {
                    const maybe_str: ?[]const u8 = if (str_value.len == 0) null else str_value;
                    try Manufacturer.set_website(db, idx, maybe_str);
                }
            },
            .wiki => {
                mfr.wiki = str_value;
                if (valid) {
                    const maybe_str: ?[]const u8 = if (str_value.len == 0) null else str_value;
                    try Manufacturer.set_wiki(db, idx, maybe_str);
                }
            },
        }
        break;
    }

    const render_data = .{
        .validating = true,
        .valid = valid,
        .saved = valid,
        .err = message,
        .mfr = mfr,
        .post_prefix = post_prefix,
    };

    switch (field) {
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

const validate_name = @import("../mfr.zig").validate_name;
const validate_year = @import("../mfr.zig").validate_year;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
