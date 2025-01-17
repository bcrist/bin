pub const Result = struct {
    relevance: f64, 
    item: DB.Any_Index,

    pub fn order(_: void, a: Result, b: Result) bool {
        return a.relevance > b.relevance;
    }

    pub fn url(self: Result, db: *const DB, arena: std.mem.Allocator) ![]const u8 {
        switch (self.item) {
            .mfr => |idx| {
                return try std.fmt.allocPrint(arena, "/mfr:{}", .{
                    http.fmtForUrl(DB.Manufacturer.get_id(db, idx)),
                });
            },
            .dist => |idx| {
                return try std.fmt.allocPrint(arena, "/dist:{}", .{
                    http.fmtForUrl(DB.Distributor.get_id(db, idx)),
                });
            },
            .part => |idx| {
                const id = DB.Part.get_id(db, idx);
                if (DB.Part.get_mfr(db, idx)) |mfr_idx| {
                    const mfr_id = DB.Manufacturer.get_id(db, mfr_idx);
                    return try std.fmt.allocPrint(arena, "/mfr:{}/p:{}", .{
                        http.fmtForUrl(mfr_id),
                        http.fmtForUrl(id),
                    });
                }
                return try std.fmt.allocPrint(arena, "/p:{}", .{ http.fmtForUrl(id) });
            },
            .order => |idx| {
                return try std.fmt.allocPrint(arena, "/o:{}", .{
                    http.fmtForUrl(DB.Order.get_id(db, idx)),
                });
            },
            .prj => |idx| {
                return try std.fmt.allocPrint(arena, "/prj:{}", .{
                    http.fmtForUrl(DB.Project.get_id(db, idx)),
                });
            },
            .pkg => |idx| {
                return try std.fmt.allocPrint(arena, "/pkg:{}", .{
                    http.fmtForUrl(DB.Package.get_id(db, idx)),
                });
            },
            .loc => |idx| {
                return try std.fmt.allocPrint(arena, "/loc:{}", .{
                    http.fmtForUrl(DB.Location.get_id(db, idx)),
                });
            },
        }
    }
};

pub const Query_Options = struct {
    max_results: ?usize = null,
    enable_by_kind: ?struct {
        mfrs: bool = false,
        dists: bool = false,
        parts: bool = false,
        orders: bool = false,
        prjs: bool = false,
        pkgs: bool = false,
        locs: bool = false,
    } = null,
};

pub fn query(db: *const DB, allocator: std.mem.Allocator, q: []const u8, options: Query_Options) ![]Result {
    if (q.len == 0) {
        return &.{};
    }

    var items = Relevance_Data.init(allocator);
    defer items.deinit();

    if (if (options.enable_by_kind) |e| e.mfrs else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "mfr:")) {
            bonus_relevance = 100;
            qq = q["mfr:".len..];
        }

        var iter = db.mfr_lookup.iterator();
        while (iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.*)) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    if (if (options.enable_by_kind) |e| e.dists else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "dist:")) {
            bonus_relevance = 100;
            qq = q["dist:".len..];
        }

        var iter = db.dist_lookup.iterator();
        while (iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.*)) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    if (if (options.enable_by_kind) |e| e.parts else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "p:")) {
            bonus_relevance = 100;
            qq = q["p:".len..];
        }

        var iter = db.part_lookup.iterator();
        while (iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.@"1")) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    if (if (options.enable_by_kind) |e| e.pkgs else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "pkg:")) {
            bonus_relevance = 100;
            qq = q["pkg:".len..];
        }

        var iter = db.pkg_lookup.iterator();
        while (iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.@"1")) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    if (if (options.enable_by_kind) |e| e.locs else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "loc:")) {
            bonus_relevance = 100;
            qq = q["loc:".len..];
        }

        var name_iter = db.loc_lookup.iterator();
        while (name_iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.*)) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    if (if (options.enable_by_kind) |e| e.prjs else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "prj:")) {
            bonus_relevance = 100;
            qq = q["prj:".len..];
        }

        var name_iter = db.prj_lookup.iterator();
        while (name_iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.*)) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    if (if (options.enable_by_kind) |e| e.orders else true) {
        var qq = q;
        var bonus_relevance: f64 = 0;
        if (std.mem.startsWith(u8, q, "o:")) {
            bonus_relevance = 100;
            qq = q["o:".len..];
        }

        var name_iter = db.order_lookup.iterator();
        while (name_iter.next()) |entry| {
            if (name_relevance(qq, entry.key_ptr.*)) |relevance| {
                try items.update(DB.Any_Index.init(entry.value_ptr.*), relevance + bonus_relevance);
            }
        }
    }

    return try items.to_results(options.max_results);
}

fn name_relevance(q: []const u8, name: []const u8) ?f64 {
    if (std.ascii.indexOfIgnoreCase(name, q)) |start_of_match| {
        var relevance: f64 = @floatFromInt(q.len);
        relevance /= @floatFromInt(1 + name.len - q.len);
        if (start_of_match == 0) {
            relevance *= 2;
        }
        return relevance;
    }
    return null;
}

const Relevance_Data = struct {
    relevances: std.AutoHashMap(DB.Any_Index, f64),

    pub fn init(allocator: std.mem.Allocator) Relevance_Data {
        return .{
            .relevances = std.AutoHashMap(DB.Any_Index, f64).init(allocator),
        };
    }

    pub fn deinit(self: *Relevance_Data) void {
        self.relevances.deinit();
    }

    pub fn update(self: *Relevance_Data, item: DB.Any_Index, relevance: f64) !void {
        const result = try self.relevances.getOrPut(item);
        if (result.found_existing) {
            if (relevance > result.value_ptr.*) {
                result.value_ptr.* = relevance;
            }
        } else {
            result.key_ptr.* = item;
            result.value_ptr.* = relevance;
        }
    }

    pub fn to_results(self: *Relevance_Data, maybe_max_results: ?usize) ![]Result {
        var results = try std.ArrayList(Result).initCapacity(self.relevances.allocator, self.relevances.count());
        var iter = self.relevances.iterator();
        while (iter.next()) |entry| {
            results.appendAssumeCapacity(.{
                .relevance = entry.value_ptr.*,
                .item = entry.key_ptr.*,
            });
        }

        std.sort.block(Result, results.items, {}, Result.order);

        if (maybe_max_results) |max_results| if (results.items.len > max_results) {
            results.shrinkAndFree(max_results);
        };

        return try results.toOwnedSlice();
    }
};

const DB = @import("DB.zig");
const http = @import("http");
const std = @import("std");
