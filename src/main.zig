pub fn main() !void {
    defer global.deinit();

    try tempora.tzdb.init_cache(global.gpa());
    defer tempora.tzdb.deinit_cache();

    config = try Config.load(global.arena());
    // config.user is used for session tracking, and we might need to reallocate it later.
    // So we want to ensure that after this point, it is always managed by global.gpa():
    config.user = try global.gpa().dupe(Session, config.user);
    defer global.gpa().free(config.user);
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

    const Injector = http.Default_Injector
        .extend(Session.inject)
        .extend(inject)
        ;

    var server = http.Server(Injector).init(global.gpa());
    defer server.deinit();

    const misc = @import("http/misc.zig");
    const mfr = @import("http/mfr.zig");
    const debug = @import("http/debug.zig");
    _ = debug;

    const r = http.routing;
    try server.register("", Session.setup);
    try server.router("", .{
        .{ "/",         r.module(Injector, misc.entry) },
        .{ "/login",    r.module(Injector, misc.login) },
        .{ "/logout",   r.module(Injector, misc.logout) },
        .{ "/shutdown", r.module(Injector, misc.shutdown) },
        .{ "/nil",      r.static_internal(.{
            .content = "",
            .cache_control = "max-age=31536000, immutable, public",
            .last_modified_utc = tempora.Date_Time.epoch,
            .etag = "nil",
        })},

        .{ "/mfr",                      r.module(Injector, mfr.list) },
        .{ "/mfr/add",                  r.module(Injector, mfr.add) },
        .{ "/mfr/add/validate",         r.module(Injector, mfr.add.validate) },
        .{ "/mfr/id",                   r.module(Injector, mfr.add.validate) },
        .{ "/mfr/full_name",            r.module(Injector, mfr.add.validate) },
        .{ "/mfr/country",              r.module(Injector, mfr.add.validate) },
        .{ "/mfr/countries",            r.module(Injector, mfr.countries) },
        .{ "/mfr/founded_year",         r.module(Injector, mfr.add.validate) },
        .{ "/mfr/suspended_year",       r.module(Injector, mfr.add.validate) },
        .{ "/mfr/website",              r.module(Injector, mfr.add.validate) },
        .{ "/mfr/wiki",                 r.module(Injector, mfr.add.validate) },
        .{ "/mfr/notes",                r.module(Injector, mfr.add.validate) },
        .{ "/mfr/additional_name",      r.module(Injector, mfr.add.validate_additional_name) },
        .{ "/mfr/relation",             r.module(Injector, mfr.add.validate_relation) },
        .{ "/mfr/relation/kinds",       r.module(Injector, mfr.relation_kinds) },
        .{ "/mfr:*",                    r.module(Injector, mfr) },
        .{ "/mfr:*/id",                 r.module(Injector, mfr.edit) },
        .{ "/mfr:*/full_name",          r.module(Injector, mfr.edit) },
        .{ "/mfr:*/country",            r.module(Injector, mfr.edit) },
        .{ "/mfr:*/founded_year",       r.module(Injector, mfr.edit) },
        .{ "/mfr:*/suspended_year",     r.module(Injector, mfr.edit) },
        .{ "/mfr:*/website",            r.module(Injector, mfr.edit) },
        .{ "/mfr:*/wiki",               r.module(Injector, mfr.edit) },
        .{ "/mfr:*/notes",              r.module(Injector, mfr.edit) },
        .{ "/mfr:*/additional_name",    r.module(Injector, mfr.edit.additional_name) },
        .{ "/mfr:*/additional_names",   r.module(Injector, mfr.edit.additional_names) },
        .{ "/mfr:*/relation",           r.module(Injector, mfr.edit.relation) },
        .{ "/mfr:*/relations",          r.module(Injector, mfr.edit.relations) },



        .{ "/o:*",      r.module(Injector, @import("http/order.zig")) },
        .{ "/prj:*",    r.module(Injector, @import("http/project.zig")) },
        .{ "/s:*",      r.module(Injector, @import("http/stock.zig")) },
        .{ "/loc:*",    r.module(Injector, @import("http/location.zig")) },
        .{ "/p:*",      r.module(Injector, @import("http/part.zig")) },
        .{ "/dist:*",   r.module(Injector, @import("http/distributor.zig")) },
        .{ "/pkg:*",    r.module(Injector, @import("http/package.zig")) },
        .{ "/param:*",  r.module(Injector, @import("http/parameter.zig")) },
        .{ "/f:*",      r.module(Injector, @import("http/file.zig")) },

        .{ "/favicon.ico", r.resource("favicon.png")[1] },

        r.resource("style.css"),
        r.resource("fonts.css"),
        r.resource("common.js"),
        r.resource("htmx.1.9.10.min.js"),
        r.resource("Sortable.1.15.2.min.js"),
        r.resource("slimselect.2.7.0.min.js"),
        r.resource("slimselect.2.7.0.mod.css"),
        r.resource("icons.woff2"),
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

var config: Config = .{};
var config_mutex: std.Thread.Mutex = .{};

var db: DB = undefined;
var db_lock: std.Thread.RwLock = .{};

threadlocal var thread_rnd: ?std.rand.Xoshiro256 = null;

const inject = struct {
    pub fn inject_config() Config {
        return config;
    }

    pub fn inject_mutable_config() *Config {
        mutex_log.debug("acquiring Config lock", .{});
        config_mutex.lock();
        return &config;
    }
    pub fn inject_mutable_config_cleanup(_: *Config) void {
        mutex_log.debug("releasing Config lock", .{});
        config_mutex.unlock();
    }

    pub fn inject_db_readonly() *const DB {
        mutex_log.debug("locking DB for reading", .{});
        db_lock.lockShared();
        return &db;
    }
    pub fn inject_db_readonly_cleanup(_: *const DB) void {
        mutex_log.debug("releasing DB read lock", .{});
        db_lock.unlockShared();
    }

    pub fn inject_db(req: *http.Request, session: ?Session) !*DB {
        try Session.redirect_if_missing(req, session);
        mutex_log.debug("locking DB for writing", .{});
        db_lock.lock();
        return &db;
    }
    pub fn inject_db_cleanup(_: *DB) void {
        mutex_log.debug("releasing DB write lock", .{});
        db_lock.unlock();
    }

    pub fn inject_rnd() *std.rand.Xoshiro256 {
        if (thread_rnd) |*rnd| return rnd;
        thread_rnd = std.rand.Xoshiro256.init(std.crypto.random.int(u64));
        return &thread_rnd.?;
    }
};

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .sx, .level = .info },
        .{ .scope = .db, .level = .info },
        .{ .scope = .@"db.intern", .level = .info },
        .{ .scope = .zkittle, .level = .info },
        .{ .scope = .http, .level = .info },
        .{ .scope = .@"http.temp", .level = .info },
        .{ .scope = .mutex, .level = .info },
        .{ .scope = .session, .level = .info },
    },
};

pub const resources = @import("http_resources");

const mutex_log = std.log.scoped(.mutex);

const DB = @import("DB.zig");
const Session = @import("Session.zig");
const Config = @import("Config.zig");
const global = @import("global.zig");
const tempora = @import("tempora");
const http = @import("http");
const std = @import("std");
