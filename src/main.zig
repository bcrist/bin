pub var config: Config = .{};
pub var db: DB = undefined;

pub fn main() !void {
    defer global.deinit();

    try tempora.tzdb.init_cache(global.gpa());
    defer tempora.tzdb.deinit_cache();

    config = try Config.load(global.arena());
    defer config.save() catch {};

    db = .{
        .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        .container_alloc = global.gpa(),
    };
    defer db.deinit();

    {
        var db_dir = try std.fs.cwd().makeOpenPath(config.db, .{ .iterate = true });
        defer db_dir.close();
        try db.import_data(&db_dir, .{ .loading = true, });
    }

    if (config.import) |import_path| {
        var import_dir = try std.fs.cwd().makeOpenPath(import_path, .{ .iterate = true });
        defer import_dir.close();
        try db.import_data(&import_dir, .{ .prefix = import_path });
    }

    {
        var db_dir = try std.fs.cwd().makeOpenPath(config.db, .{});
        defer db_dir.close();
        try db.export_data(&db_dir);
    }

    db.recompute_last_modification_time();

    // TODO start thread to periodically write any changes back to db dir

    const Injector = http.Default_Injector;
    var server = http.Server(Injector).init(global.gpa());
    defer server.deinit();

    const r = http.routing;
    try server.router("", .{
        .{ "/", r.generic("index.htm") },
        .{ "/login", r.generic("login.htm") },
        .{ "/shutdown", r.method(.GET), r.shutdown, r.generic("shutdown.htm") },

        .{ "/o:*",     r.module(Injector, @import("http/order.zig")) },
        .{ "/prj:*",   r.module(Injector, @import("http/project.zig")) },
        .{ "/s:*",     r.module(Injector, @import("http/stock.zig")) },
        .{ "/loc:*",   r.module(Injector, @import("http/location.zig")) },
        .{ "/p:*",     r.module(Injector, @import("http/part.zig")) },
        .{ "/mfr:*",   r.module(Injector, @import("http/manufacturer.zig")) },
        .{ "/dist:*",  r.module(Injector, @import("http/distributor.zig")) },
        .{ "/pkg:*",   r.module(Injector, @import("http/package.zig")) },
        .{ "/param:*", r.module(Injector, @import("http/parameter.zig")) },
        .{ "/f:*",     r.module(Injector, @import("http/file.zig")) },

        r.resource("style.css"),
        r.resource("htmx.1.9.10.min.js"),
        r.resource("montserrat_normal_latin.woff2"),
        r.resource("montserrat_normal_latin_ext.woff2"),
        r.resource("montserrat_italic_latin.woff2"),
        r.resource("montserrat_italic_latin_ext.woff2"),
        r.resource("noto_sans_normal_latin.woff2"),
        r.resource("noto_sans_normal_latin_ext.woff2"),
        r.resource("noto_sans_normal_greek.woff2"),
        r.resource("noto_sans_italic_latin.woff2"),
        r.resource("noto_sans_italic_latin_ext.woff2"),
        r.resource("noto_sans_italic_greek.woff2"),
        r.resource("roboto_slab_latin.woff2"),
        r.resource("roboto_slab_latin_ext.woff2"),
        r.resource("roboto_slab_greek.woff2"),
    });
    
    const listen_addr = try http.parse_hostname(global.gpa(), config.host, config.port);
    try server.start(.{
        .address = listen_addr,
        .connection_threads = config.http_threads,
    });

    try server.run();
}

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .db_intern, .level = .info },
    },
};

pub const resources = @import("http_resources");

const DB = @import("DB.zig");
const Config = @import("Config.zig");
const global = @import("global.zig");
const tempora = @import("tempora");
const http = @import("http");
const std = @import("std");
