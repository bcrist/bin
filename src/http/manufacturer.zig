pub fn get(req: *http.Request, db: *const DB, temp: std.mem.Allocator) !void {
    const requested = try http.percent_encoding.decode_alloc(temp, req.get_path_param("mfr").?);
    const idx = db.mfr_lookup.get(requested) orelse return;
    const mfr = db.mfrs.get(@intFromEnum(idx));

    _ = try req.maybe_add_response_header("content-type", http.content_type.html);
    _ = try req.maybe_add_response_header("cache-control", "must-revalidate, max-age=600, private");
    const response = try req.response();
    const source = http.routing.resource_content("mfr.htm");
    try http.template.render(source, mfr, response.writer(), .{
        .resource_path = http.routing.resource_path_anyerror,
        .resource_content = http.routing.resource_content_anyerror,
    });
}

const Manufacturer = DB.Manufacturer;
const DB = @import("../DB.zig");
const http = @import("http");
const std = @import("std");
