username: []const u8 = "admin",
password: []const u8 = "admin",
token: ?Token = null,

const Session = @This();

pub const Token = [88]u8;

pub const context = struct {
    pub const inline_fields = &.{ "username" };
};

threadlocal var maybe_session: ?Session = null;

pub fn setup(req: *http.Request, config: Config) !void {
    var iter = req.header_iterator();
    while (iter.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "Cookie")) {
            if (std.mem.indexOfScalar(u8, header.value, '=')) |end_of_key| {
                const key = header.value[0..end_of_key];
                if (std.mem.eql(u8, key, "st")) {
                    const remaining = header.value[end_of_key + 1 ..];
                    const end_of_token = std.mem.indexOfScalar(u8, remaining, ';') orelse remaining.len;
                    const token = remaining[0..end_of_token];

                    if (maybe_session) |session| {
                        if (try check_token(req, token, session)) return;
                    }

                    for (config.user) |session| {
                        if (try check_token(req, token, session)) {
                            maybe_session = session;
                            return;
                        }
                    }

                    log.info("Provided session token does not match any known user; removing cookie", .{});
                    try remove_cookie(req);
                    maybe_session = null;
                    return;
                }
            }
        }
    }

    log.debug("No session cookie provided by client; resetting thread local", .{});
    maybe_session = null;
}

fn check_token(req: *http.Request, found_token: []const u8, session: Session) !bool {
    if (session.token) |*user_token| {
        if (std.mem.eql(u8, found_token, user_token)) {
            log.debug("Continuing session {s}", .{ user_token });
            try add_cookie(req, user_token);
            return true;
        }
    }
    return false;
}

pub fn remove_cookie(req: *http.Request) !void {
    try req.add_response_header("Set-Cookie", "st=_; Path=/; Secure; HttpOnly; SameSite=Strict; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
}

pub fn add_cookie(req: *http.Request, token: *const Token) !void {
    const cookie = try std.fmt.allocPrint(http.temp(), "st={s}; Path=/; Secure; HttpOnly; SameSite=Strict", .{ token });
    try req.add_response_header("Set-Cookie", cookie);
}

/// N.B. if you want to change data in the Session, you should also generate a new random token and
/// send it to the client with a Set-Cookie header.  This will ensure any other threads' `maybe_session`
/// threadlocal will be replaced upon handling the next request with the new token.
pub fn update(req: *http.Request, config: *Config, index: usize, session: Session) !void {
    const new_sessions = try global.gpa().dupe(Session, config.user);
    new_sessions[index] = session;

    global.gpa().free(config.user);
    config.user = new_sessions;

    if (session.token) |*token| {
        log.info("User {s} logged in", .{ session.username });
        log.debug("Session token for user {s} is {s}", .{ session.username, token });
        maybe_session = session;
        try add_cookie(req, token);
    } else {
        log.info("User {s} logged out", .{ session.username });
        maybe_session = null;
        try remove_cookie(req);
    }
}

pub fn reset(req: *http.Request) !void {
    log.debug("Resetting session", .{});
    maybe_session = null;
    try remove_cookie(req);
}

pub fn generate_token() Token {
    var bytes: [64]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    var result: Token = undefined;
    const encoder = std.base64.standard.Encoder;
    std.debug.assert(encoder.calcSize(bytes.len) == result.len);
    _ = encoder.encode(&result, &bytes);

    return result;
}

pub const inject = struct {
    pub fn inject_session() ?Session {
        return maybe_session;
    }
};

const log = std.log.scoped(.session);

const Config = @import("Config.zig");
const global = @import("global.zig");
const http = @import("http");
const std = @import("std");
