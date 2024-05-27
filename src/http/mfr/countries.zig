pub fn get(req: *http.Request, db: *const DB) !void {
    var set = std.StringArrayHashMap(void).init(http.temp());
    for (db.mfrs.items(.country)) |maybe_country| {
        if (maybe_country) |country| {
            try set.put(country, {});
        }
    }

    const countries = set.keys();
    sort.lexicographic(countries);

    var options = try std.ArrayList(slimselect.Option).initCapacity(http.temp(), countries.len + 1);

    options.appendAssumeCapacity(.{
        .placeholder = true,
        .value = "",
        .text = " ",
    });

    for (countries) |country| {
        options.appendAssumeCapacity(.{
            .value = country,
            .text = country,
        });
    }

    try slimselect.respond_with_options(req, options.items);
}

const DB = @import("../../DB.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
