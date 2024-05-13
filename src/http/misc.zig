pub const entry = struct {
    pub fn get(session: ?Session, req: *http.Request) !void {
        try req.render("index.zk", .{
            .session = session,
        }, .{});
    }
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
                    try req.respond_err(.{ .status = .unsupported_media_type });
                }
            }
        }

        var buf: [4096]u8 = undefined;
        const reader = try req.req.reader();
        const bytes = try reader.readAll(&buf);

        var redirect: []const u8 = "/";
        var username: []const u8 = "";
        var password: []const u8 = "";

        var iter = http.query_iterator(http.temp(), buf[0..bytes]);
        while (try iter.next()) |param| {
            if (std.mem.eql(u8, param.name, "username")) {
                username = try http.temp().dupe(u8, param.value orelse "");
            } else if (std.mem.eql(u8, param.name, "password")) {
                password = try http.temp().dupe(u8, param.value orelse "");
            } else if (std.mem.eql(u8, param.name, "redirect")) {
                redirect = try http.temp().dupe(u8, param.value orelse "/");
            }
        }

        for (0.., config.user) |index, user| {
            if (std.mem.eql(u8, username, user.username)) {
                if (std.mem.eql(u8, password, user.password)) {
                    var new_session = user;
                    new_session.token = Session.generate_token();

                    try Session.update(req, config, index, new_session);
                } else {
                    redirect = "/login?failed";
                }
                break;
            }
        } else {
            redirect = "/login?failed";
        }
        
        try req.add_response_header("Location", redirect);
        try req.respond_err(.{ .status = .see_other, .empty_content = true });
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

        try req.add_response_header("Location", redirect);
        try req.respond_err(.{ .status = .see_other, .empty_content = true });
    }
};

pub const shutdown = struct {
    pub fn get(session: ?Session, req: *http.Request, pool: *http.Thread_Pool) !void {
        if (session == null) {
            try req.respond_err(.{ .status = std.http.Status.unauthorized });
            return;
        }
        try http.routing.shutdown(req, pool);
        try req.render("shutdown.htm", {}, .{});
    }
};

const log = std.log.scoped(.http);

const Config = @import("../Config.zig");
const Session = @import("../Session.zig");
const http = @import("http");
const std = @import("std");
