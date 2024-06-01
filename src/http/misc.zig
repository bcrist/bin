pub const entry = struct {
    const DTO = tempora.Date_Time.With_Offset;
    pub fn get(session: ?Session, req: *http.Request, db: *const DB) !void {
        const tz = if (session) |s| try tempora.tzdb.timezone(s.timezone) else null;
        const last_modified = DTO.from_timestamp_ms(db.last_modification_timestamp_ms orelse 0, null).in_timezone(tz);
        try req.render("index.zk", .{
            .session = session,
            .last_modified = last_modified,
            .dirty = db.dirty_timestamp_ms != null,
        }, .{ .Context = Context });
    }

    const Context = struct {
        pub const last_modified = DTO.fmt_sql;
    };
};

pub const login = struct {
    pub fn get(session: ?Session, req: *http.Request) !void {
        try req.render("login.zk", .{
            .session = session,
            .failed = try req.has_query_param("failed"),
            .redirect = try req.get_query_param("redirect"),
        }, .{});
    }

    pub fn post(req: *http.Request, config: *Config) !void {
        var header_iter = req.header_iterator();
        while (header_iter.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "Content-type")) {
                if (!std.mem.startsWith(u8, header.value, http.content_type.without_encoding.form_urlencoded)) {
                    return error.UnsupportedMediaType;
                }
            }
        }

        var redirect: []const u8 = "/";
        var username: []const u8 = "";
        var password: []const u8 = "";

        var iter = try req.form_iterator();
        while (try iter.next()) |param| {
            if (std.mem.eql(u8, param.name, "username")) {
                username = try http.temp().dupe(u8, param.value orelse "");
            } else if (std.mem.eql(u8, param.name, "password")) {
                password = try http.temp().dupe(u8, param.value orelse "");
            } else if (std.mem.eql(u8, param.name, "redirect")) {
                redirect = try http.temp().dupe(u8, param.value orelse "/");
            }
        }

        var failed = false;
        for (0.., config.user) |index, user| {
            if (std.mem.eql(u8, username, user.username)) {
                if (std.mem.eql(u8, password, user.password)) {
                    var new_session = user;
                    new_session.token = Session.generate_token();

                    try Session.update(req, config, index, new_session);
                } else {
                    failed = true;
                }
                break;
            }
        } else {
            failed = true;
        }

        if (failed) {
            var redirect_temp = try std.ArrayList(u8).initCapacity(http.temp(), 64 + redirect.len);
            redirect_temp.appendSliceAssumeCapacity("/login?failed&redirect=");
            _ = try http.percent_encoding.encode_append(&redirect_temp, redirect, .encode_other_and_reserved);
            redirect = redirect_temp.items;
        }
        
        req.response_status = .see_other;
        try req.add_response_header("Location", redirect);
        try req.respond("");
    }
};

pub const logout = struct {
    pub fn get(session: ?Session, req: *http.Request, config: *Config) !void {
        const maybe_redirect = try req.get_query_param("redirect");
        const redirect = maybe_redirect orelse "/";

        if (session) |s| {
            for (0.., config.user) |index, user| {
                if (std.mem.eql(u8, s.username, user.username)) {
                    var new_session = user;
                    new_session.token = null;
                    try Session.update(req, config, index, new_session);
                    break;
                }
            } else {
                try Session.reset(req);
            }
        }

        req.response_status = .see_other;
        try req.add_response_header("Location", redirect);
        try req.respond("");
    }
};

pub const shutdown = struct {
    pub fn get(session: ?Session, req: *http.Request, pool: *http.Thread_Pool) !void {
        if (session == null) {
            return error.Unauthorized;
        }
        try http.routing.shutdown(req, pool);
        try req.render("shutdown.htm", {}, .{});
    }
};

const log = std.log.scoped(.http);

const DB = @import("../DB.zig");
const Config = @import("../Config.zig");
const Session = @import("../Session.zig");
const tempora = @import("tempora");
const http = @import("http");
const std = @import("std");
