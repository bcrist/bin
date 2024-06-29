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

    try db.import_data(.{
        .path = config.db,
        .loading = true,
    });

    if (config.import) |import_path| {
        try db.import_data(.{ .path = import_path });
    }

    try persist();
    db.recompute_last_modification_time();
    persist_thread = try std.Thread.spawn(.{}, persist_thread_task, .{});

    const Injector = http.Default_Injector
        .extend(Session.inject)
        .extend(inject)
        ;

    var server = http.Server(Injector).init(global.gpa());
    defer server.deinit();

    const misc = @import("http/misc.zig");
    const search = @import("http/search.zig");
    const mfr = @import("http/mfr.zig");
    const dist = @import("http/dist.zig");
    const loc = @import("http/loc.zig");
    const pkg = @import("http/pkg.zig");
    const part = @import("http/part.zig");

    const r = http.routing;
    try server.register("", Session.setup);
    try server.router("", .{
        .{ "/", r.module(Injector, misc.entry) },
        .{ "/nil", r.static_internal(.{
            .content = "",
            .cache_control = "max-age=31536000, immutable, public",
            .last_modified_utc = tempora.Date_Time.epoch,
            .etag = "nil",
        })},

        .{ "/search", r.module(Injector, search) },

        .{ "/mfr**" },
        .{ "/dist**" },
        .{ "/loc**" },
        .{ "/pkg**" },
        .{ "/p**" },
        // .{ "/o:*" },
        // .{ "/prj:*" },
        // .{ "/param:*" },
        // .{ "/f:*" },

        .{ "/login", r.module(Injector, misc.login) },
        .{ "/logout", r.module(Injector, misc.logout) },
        .{ "/shutdown", r.module(Injector, misc.shutdown) },

        .{ "/favicon.ico", r.resource("favicon.png")[1] },

        r.resource("style.css"),
        r.resource("fonts.css"),
        r.resource("common.js"),
        r.resource("htmx.1.9.12.min.js"),
        r.resource("htmx.1.9.12.js"),
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

    try server.router("/mfr**", .{
        .{ "",                      r.module(Injector, mfr.list) },
        .{ "/add",                  r.module(Injector, mfr.add) },
        .{ "/add/validate",         r.module(Injector, mfr.add.validate) },
        .{ "/id",                   r.module(Injector, mfr.add.validate) },
        .{ "/full_name",            r.module(Injector, mfr.add.validate) },
        .{ "/country",              r.module(Injector, mfr.add.validate) },
        .{ "/countries",            r.module(Injector, mfr.countries) },
        .{ "/founded_year",         r.module(Injector, mfr.add.validate) },
        .{ "/suspended_year",       r.module(Injector, mfr.add.validate) },
        .{ "/website",              r.module(Injector, mfr.add.validate) },
        .{ "/wiki",                 r.module(Injector, mfr.add.validate) },
        .{ "/notes",                r.module(Injector, mfr.add.validate) },
        .{ "/additional_name",      r.module(Injector, mfr.add.validate_additional_name) },
        .{ "/additional_name:*",    r.module(Injector, mfr.add.validate_additional_name) },
        .{ "/relation",             r.module(Injector, mfr.add.validate_relation) },
        .{ "/relation:*",           r.module(Injector, mfr.add.validate_relation) },
        .{ "/relation/kinds",       r.module(Injector, mfr.relation_kinds) },
        .{ ":*",                    r.module(Injector, mfr) },
        .{ ":*/id",                 r.module(Injector, mfr.edit) },
        .{ ":*/full_name",          r.module(Injector, mfr.edit) },
        .{ ":*/country",            r.module(Injector, mfr.edit) },
        .{ ":*/founded_year",       r.module(Injector, mfr.edit) },
        .{ ":*/suspended_year",     r.module(Injector, mfr.edit) },
        .{ ":*/website",            r.module(Injector, mfr.edit) },
        .{ ":*/wiki",               r.module(Injector, mfr.edit) },
        .{ ":*/notes",              r.module(Injector, mfr.edit) },
        .{ ":*/additional_name",    r.module(Injector, mfr.edit.additional_name) },
        .{ ":*/additional_name:*",  r.module(Injector, mfr.edit.additional_name) },
        .{ ":*/additional_names",   r.module(Injector, mfr.reorder_additional_names) },
        .{ ":*/relation",           r.module(Injector, mfr.edit.relation) },
        .{ ":*/relation:*",         r.module(Injector, mfr.edit.relation) },
        .{ ":*/relations",          r.module(Injector, mfr.reorder_relations) },

        .{ ":*/p**", "/p**" }, // anything like /mfr:whatever/p:* gets handled the same way as /p:*
    });

    try server.router("/dist**", .{
        .{ "",                      r.module(Injector, dist.list) },
        .{ "/add",                  r.module(Injector, dist.add) },
        .{ "/add/validate",         r.module(Injector, dist.add.validate) },
        .{ "/id",                   r.module(Injector, dist.add.validate) },
        .{ "/full_name",            r.module(Injector, dist.add.validate) },
        .{ "/country",              r.module(Injector, dist.add.validate) },
        .{ "/countries",            r.module(Injector, dist.countries) },
        .{ "/founded_year",         r.module(Injector, dist.add.validate) },
        .{ "/suspended_year",       r.module(Injector, dist.add.validate) },
        .{ "/website",              r.module(Injector, dist.add.validate) },
        .{ "/wiki",                 r.module(Injector, dist.add.validate) },
        .{ "/notes",                r.module(Injector, dist.add.validate) },
        .{ "/additional_name",      r.module(Injector, dist.add.validate_additional_name) },
        .{ "/additional_name:*",    r.module(Injector, dist.add.validate_additional_name) },
        .{ "/relation",             r.module(Injector, dist.add.validate_relation) },
        .{ "/relation:*",           r.module(Injector, dist.add.validate_relation) },
        .{ "/relation/kinds",       r.module(Injector, dist.relation_kinds) },
        .{ ":*",                    r.module(Injector, dist) },
        .{ ":*/id",                 r.module(Injector, dist.edit) },
        .{ ":*/full_name",          r.module(Injector, dist.edit) },
        .{ ":*/country",            r.module(Injector, dist.edit) },
        .{ ":*/founded_year",       r.module(Injector, dist.edit) },
        .{ ":*/suspended_year",     r.module(Injector, dist.edit) },
        .{ ":*/website",            r.module(Injector, dist.edit) },
        .{ ":*/wiki",               r.module(Injector, dist.edit) },
        .{ ":*/notes",              r.module(Injector, dist.edit) },
        .{ ":*/additional_name",    r.module(Injector, dist.edit.additional_name) },
        .{ ":*/additional_name:*",  r.module(Injector, dist.edit.additional_name) },
        .{ ":*/additional_names",   r.module(Injector, dist.reorder_additional_names) },
        .{ ":*/relation",           r.module(Injector, dist.edit.relation) },
        .{ ":*/relation:*",         r.module(Injector, dist.edit.relation) },
        .{ ":*/relations",          r.module(Injector, dist.reorder_relations) },
    });

    try server.router("/loc**", .{
        .{ "",              r.module(Injector, loc.list) },
        .{ "/add",          r.module(Injector, loc.add) },
        .{ "/add/validate", r.module(Injector, loc.add.validate) },
        .{ "/id",           r.module(Injector, loc.add.validate) },
        .{ "/full_name",    r.module(Injector, loc.add.validate) },
        .{ "/notes",        r.module(Injector, loc.add.validate) },
        .{ "/parent",       r.module(Injector, loc.add.validate) },
        .{ ":*",            r.module(Injector, loc) },
        .{ ":*/id",         r.module(Injector, loc.edit) },
        .{ ":*/full_name",  r.module(Injector, loc.edit) },
        .{ ":*/notes",      r.module(Injector, loc.edit) },
        .{ ":*/parent",     r.module(Injector, loc.edit) },
    });

    try server.router("/pkg**", .{
        .{ "",                     r.module(Injector, pkg.list) },
        .{ "/add",                 r.module(Injector, pkg.add) },
        .{ "/add/validate",        r.module(Injector, pkg.add.validate) },
        .{ "/id",                  r.module(Injector, pkg.add.validate) },
        .{ "/full_name",           r.module(Injector, pkg.add.validate) },
        .{ "/notes",               r.module(Injector, pkg.add.validate) },
        .{ "/parent",              r.module(Injector, pkg.add.validate) },
        .{ "/mfr",                 r.module(Injector, pkg.add.validate) },
        .{ "/additional_name",     r.module(Injector, pkg.add.validate_additional_name) },
        .{ "/additional_name:*",   r.module(Injector, pkg.add.validate_additional_name) },
        .{ ":*",                   r.module(Injector, pkg) },
        .{ ":*/id",                r.module(Injector, pkg.edit) },
        .{ ":*/full_name",         r.module(Injector, pkg.edit) },
        .{ ":*/notes",             r.module(Injector, pkg.edit) },
        .{ ":*/parent",            r.module(Injector, pkg.edit) },
        .{ ":*/mfr",               r.module(Injector, pkg.edit) },
        .{ ":*/additional_name",   r.module(Injector, pkg.edit.additional_name) },
        .{ ":*/additional_name:*", r.module(Injector, pkg.edit.additional_name) },
        .{ ":*/additional_names",  r.module(Injector, pkg.reorder_additional_names) },
    });

    try server.router("/p**", .{
        .{ "",              r.module(Injector, part.list) },
        .{ "/add",          r.module(Injector, part.add) },
        .{ "/add/validate", r.module(Injector, part.add.validate) },
        .{ "/mfr",          r.module(Injector, part.add.validate) },
        .{ "/id",           r.module(Injector, part.add.validate) },
        .{ "/notes",        r.module(Injector, part.add.validate) },
        .{ "/parent_mfr",   r.module(Injector, part.add.validate) },
        .{ "/parent",       r.module(Injector, part.add.validate) },
        .{ "/pkg",          r.module(Injector, part.add.validate) },
        .{ "/dist_pn",      r.module(Injector, part.add.validate_dist_pn) },
        .{ "/dist_pn:*",    r.module(Injector, part.add.validate_dist_pn) },
        .{ ":*",            r.module(Injector, part) },
        .{ ":*/mfr",        r.module(Injector, part.edit) },
        .{ ":*/id",         r.module(Injector, part.edit) },
        .{ ":*/notes",      r.module(Injector, part.edit) },
        .{ ":*/parent_mfr", r.module(Injector, part.edit) },
        .{ ":*/parent",     r.module(Injector, part.edit) },
        .{ ":*/pkg",        r.module(Injector, part.edit) },
        .{ ":*/dist_pn",    r.module(Injector, part.edit.dist_pn) },
        .{ ":*/dist_pn:*",  r.module(Injector, part.edit.dist_pn) },
        .{ ":*/dist_pns",   r.module(Injector, part.reorder_dist_pns) },
    });
    
    const listen_addr = try http.parse_hostname(global.gpa(), config.host, config.port);
    try server.start(.{
        .address = listen_addr,
        .connection_threads = config.http_threads,
    });

    try server.run();

    mutex_log.debug("locking DB for shutdown", .{});
    db_lock.lock();
    shut_down = true;
    db_lock.unlock();

    persist_thread.join();

    try persist();
}

fn persist_thread_task() void {
    while (true) {
        var sleep_time_ms = config.persist_thread_interval_ms;
        {
            mutex_log.debug("locking DB for persist", .{});
            db_lock.lock();
            defer db_lock.unlock();

            if (shut_down) break;

            if (db.dirty_set.count() > 0) {
                if (db.last_modification_timestamp_ms) |last_mod| {
                    const ms_since_last_mod = std.time.milliTimestamp() - last_mod;
                    if (ms_since_last_mod >= config.autosave_delay_ms) {
                        persist() catch |err| {
                            std.log.scoped(.db).err("Failed to persist changes: {s}", .{ @errorName(err) });
                        };
                    } else {
                        sleep_time_ms = @min(sleep_time_ms, config.autosave_delay_ms - ms_since_last_mod);
                    }
                }
            }
        }
        std.time.sleep(@intCast(sleep_time_ms * 1_000_000));
    }
}

fn persist() !void {
    std.log.scoped(.db).debug("Beginning DB persist", .{});
    const start = std.time.microTimestamp();

    var db_dir = try std.fs.cwd().makeOpenPath(config.db, .{});
    defer db_dir.close();
    try db.export_data(&db_dir);

    const end = std.time.microTimestamp();
    std.log.scoped(.db).info("Finished DB persist (took {d:.1} ms)", .{ @as(f32, @floatFromInt(end - start)) / 1000 });
}

var config: Config = .{};
var config_mutex: std.Thread.Mutex = .{};

var db: DB = undefined;
var db_lock: std.Thread.RwLock = .{};

var shut_down: bool = false; // protected by db_lock
var persist_thread: std.Thread = undefined;

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

    pub fn inject_timezone(session: ?Session) !?*const tempora.Timezone {
        const tz_name = if (session) |s| s.timezone else config.timezone;
        return try tempora.tzdb.timezone(tz_name orelse "GMT");
    }
};

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .sx, .level = .info },
        //.{ .scope = .db, .level = .info },
        .{ .scope = .@"db.intern", .level = .info },
        .{ .scope = .zkittle, .level = .info },
        // .{ .scope = .http, .level = .info },
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
