pub const validate = @import("add/validate.zig");
pub const validate_additional_name = @import("add/validate_additional_name.zig");
pub const validate_relation = @import("add/validate_relation.zig");

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
    const alloc = http.temp();

    var another = false;

    var mfr = Manufacturer.init_empty("", std.time.milliTimestamp());
    var relations = std.StringArrayHashMap(Relation).init(alloc);

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

        if (std.mem.startsWith(u8, param.name, "additional_name")) {
            if (value.len == 0) continue;
            var valid = true;
            var message: []const u8 = "";
            const name = try validate_name(value, db, null, .{ .additional_name = null }, &valid, &message);
            if (valid) {
                try mfr.additional_names.append(alloc, try alloc.dupe(u8, name.?));
            } else {
                log.warn("Invalid additional name {s} ({s})", .{ value, message });
                return error.BadRequest;
            }

        } else if (std.mem.startsWith(u8, param.name, "relation_kind")) {
            const index_str = param.name["relation_kind".len..];
            if (index_str.len == 0) continue;
            const kind = std.meta.stringToEnum(Manufacturer.Relation.Kind, value) orelse {
                log.warn("Invalid relation kind {s} for relation {s}", .{ value, index_str });
                return error.BadRequest;
            };
            const result = try relations.getOrPut(index_str);
            if (result.found_existing) {
                result.value_ptr.kind = kind;
            } else {
                result.key_ptr.* = try alloc.dupe(u8, index_str);
                result.value_ptr.* = .{
                    .source = undefined,
                    .target = .unknown,
                    .kind = kind,
                    .year = null,
                    .source_order_index = undefined,
                    .target_order_index = 0xFFFF,
                };
            }

        } else if (std.mem.startsWith(u8, param.name, "relation_other")) {
            const index_str = param.name["relation_other".len..];
            if (index_str.len == 0) continue;
            const other = try alloc.dupe(u8, value);
            if (Manufacturer.maybe_lookup(db, other)) |idx| {
                const result = try relations.getOrPut(index_str);
                if (result.found_existing) {
                    result.value_ptr.target = idx;
                } else {
                    result.key_ptr.* = try alloc.dupe(u8, index_str);
                    result.value_ptr.* = .{
                        .source = undefined,
                        .target = idx,
                        .kind = .formerly,
                        .year = null,
                        .source_order_index = undefined,
                        .target_order_index = 0xFFFF,
                    };
                }
            } else {
                log.warn("Invalid manufacturer {s} for relation {s}", .{ value, index_str });
                return error.BadRequest;
            }

        } else if (std.mem.startsWith(u8, param.name, "relation_year")) {
            const index_str = param.name["relation_year".len..];
            if (index_str.len == 0) continue;
            var valid = true;
            var msg: []const u8 = "";
            const year = try validate_year(value, &valid, &msg);
            if (!valid) {
                log.warn("Invalid year {s} for relation {s} ({s})", .{ value, index_str, msg });
                return error.BadRequest;
            }
            const result = try relations.getOrPut(index_str);
            if (result.found_existing) {
                result.value_ptr.year = year;
            } else {
                result.key_ptr.* = try alloc.dupe(u8, index_str);
                result.value_ptr.* = .{
                    .source = undefined,
                    .target = .unknown,
                    .kind = .formerly,
                    .year = year,
                    .source_order_index = undefined,
                    .target_order_index = 0xFFFF,
                };
            }

        } else if (std.mem.startsWith(u8, param.name, "relation")) {
            continue;

        } else {
            const field = std.meta.stringToEnum(Field, param.name) orelse {
                log.warn("Unrecognized parameter: {s}", .{ param.name });
                return error.BadRequest;
            };
            const copied_value = try alloc.dupe(u8, value);
            var valid = true;
            var message: []const u8 = "";
            switch (field) {
                .id => mfr.id = try validate_name(copied_value, db, null, .id, &valid, &message) orelse "",
                .full_name => mfr.full_name = try validate_name(copied_value, db, null, .full_name, &valid, &message),
                .country => mfr.country = if (copied_value.len > 0) copied_value else null,
                .founded_year => mfr.founded_year = try validate_year(copied_value, &valid, &message),
                .suspended_year => mfr.suspended_year = try validate_year(copied_value, &valid, &message),
                .notes => mfr.notes = if (copied_value.len > 0) copied_value else null,
                .website => mfr.website = if (copied_value.len > 0) copied_value else null,
                .wiki => mfr.wiki = if (copied_value.len > 0) copied_value else null,
            }
            if (!valid) {
                log.warn("Invalid {s} parameter: {s} ({s})", .{ param.name, copied_value, message });
                return error.BadRequest;
            }
        }
    }

    for (relations.keys(), relations.values()) |index_str, relation| {
        if (relation.target == .unknown) {
            log.warn("Missing parameter: relation_other{s}", .{ index_str });
            return error.BadRequest;
        }
    }

    if (mfr.full_name) |full_name| {
        if (std.mem.eql(u8, mfr.id, full_name)) {
            mfr.full_name = null;
        }
    }

    { // remove any additional names that are duplicates of id or full_name
        const full_name_or_id = mfr.full_name orelse mfr.id;
        var i: usize = 0;
        while (i < mfr.additional_names.items.len) : (i += 1) {
            const name = mfr.additional_names.items[i];
            if (std.mem.eql(u8, mfr.id, name) or std.mem.eql(u8, full_name_or_id, name)) {
                _ = mfr.additional_names.orderedRemove(i);
                i -= 1;
            }
        }
    }

    const idx = try Manufacturer.lookup_or_create(db, mfr.id);
    try Manufacturer.set_full_name(db, idx, mfr.full_name);
    try Manufacturer.set_country(db, idx, mfr.country);
    try Manufacturer.set_website(db, idx, mfr.website);
    try Manufacturer.set_wiki(db, idx, mfr.wiki);
    try Manufacturer.set_notes(db, idx, mfr.notes);
    try Manufacturer.set_founded_year(db, idx, mfr.founded_year);
    try Manufacturer.set_suspended_year(db, idx, mfr.suspended_year);
    try Manufacturer.add_additional_names(db, idx, mfr.additional_names.items);

    for (0.., relations.values()) |i, relation| {
        var mutable_relation = relation;
        mutable_relation.source = idx;
        mutable_relation.source_order_index = @intCast(i);
        try Manufacturer.Relation.create(mutable_relation, db);
    }

    if (another) {
        if (req.get_header("hx-current-url")) |param| {
            const url = param.value;
            if (std.mem.indexOfScalar(u8, url, '?')) |query_start| {
                try req.see_other(try http.tprint("/mfr/add{s}", .{ url[query_start..] }));
                return;
            }
        }
        try req.see_other("/mfr/add");
    }

    try req.see_other(try http.tprint("/mfr:{}", .{ http.percent_encoding.fmtEncoded(mfr.id) }));
}

const log = std.log.scoped(.@"http.mfr");

const Field = @import("../mfr.zig").Field;
const render = @import("../mfr.zig").render;
const validate_name = @import("../mfr.zig").validate_name;
const validate_year = @import("../mfr.zig").validate_year;

const Relation = Manufacturer.Relation;
const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
