pub const additional_name = @import("edit/additional_name.zig");
pub const additional_names = @import("edit/additional_names.zig");
pub const relation = @import("edit/relation.zig");
pub const relations = @import("edit/relations.zig");

pub fn post(req: *http.Request, db: *DB) !void {
    const requested_mfr_name = try req.get_path_param("mfr");
    const idx = Manufacturer.maybe_lookup(db, requested_mfr_name) orelse return;
    var mfr = Manufacturer.get(db, idx);
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
                mfr.id = (try validate_name(str_value, db, idx, .id, &valid, &message)).?;
                if (valid and try Manufacturer.set_id(db, idx, mfr.id)) {
                    try req.add_response_header("HX-Location", try http.tprint("/mfr:{}?edit", .{ http.percent_encoding.fmtEncoded(mfr.id) }));
                }
            },
            .full_name => {
                mfr.full_name = try validate_name(str_value, db, idx, .full_name, &valid, &message);
                if (valid) {
                    try Manufacturer.set_full_name(db, idx, mfr.full_name);
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
            .country => {
                mfr.country = if (str_value.len > 0) str_value else null;
                try Manufacturer.set_country(db, idx, mfr.country);
            },
            .notes => {
                mfr.notes = if (str_value.len > 0) str_value else null;
                try Manufacturer.set_notes(db, idx, mfr.notes);
            },
            .website => {
                mfr.website = if (str_value.len > 0) str_value else null;
                try Manufacturer.set_website(db, idx, mfr.website);
            },
            .wiki => {
                mfr.wiki = if (str_value.len > 0) str_value else null;
                try Manufacturer.set_wiki(db, idx, mfr.wiki);
            },
        }
        break;
    }

    const render_data = .{
        .validating = true,
        .valid = valid,
        .saved = valid,
        .err = message,
        .obj = mfr,
        .country_search_url = "/mfr/countries",
        .post_prefix = post_prefix,
    };

    switch (field) {
        .id => try req.render("common/post_id.zk", render_data, .{}),
        .full_name => try req.render("common/post_full_name.zk", render_data, .{}),
        .country => try req.render("common/post_country.zk", render_data, .{}),
        .founded_year => try req.render("common/post_founded_year.zk", render_data, .{}),
        .suspended_year => try req.render("common/post_suspended_year.zk", render_data, .{}),
        .notes => try req.render("common/post_notes.zk", render_data, .{}),
        .website => try req.render("common/post_website.zk", render_data, .{}),
        .wiki => try req.render("common/post_wiki.zk", render_data, .{}),
    }
}

const log = std.log.scoped(.@"http.mfr");

const Field = @import("../mfr.zig").Field;
const validate_name = @import("../mfr.zig").validate_name;
const validate_year = @import("../mfr.zig").validate_year;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
