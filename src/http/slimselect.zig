pub const Option = struct {
    placeholder: ?bool = null,
    value: []const u8,
    text: []const u8,
};

pub fn Enum_Options(comptime E: type) type {
    return struct {
        placeholder: ?[]const u8 = null,
        display_fn: ?*const fn (e: E) []const u8 = null,
    };
}

pub fn respond_with_enum_options(req: *http.Request, comptime E: type, comptime options: Enum_Options(E)) !void {
    const build_time: tempora.Date_Time = @import("root").resources.build_time;

    try req.add_response_header("content-type", http.content_type.json);
    try req.add_response_header("cache-control", "max-age=600, public");

    // TODO make a helper for this in http.Request
    try req.add_response_header("last-modified", try http.format_http_date(http.temp(), build_time));
    if (req.get_header("if-modified-since")) |header| {
        const DTO = tempora.Date_Time.With_Offset;
        if (DTO.from_string(DTO.fmt_http, header.value)) |last_seen| {
            if (!last_seen.dt.is_before(build_time)) {
                req.response_status = .not_modified;
                try req.respond("");
                return;
            }
        } else |_| {}
    }

    comptime var data: []const Option = &.{};
    if (options.placeholder) |placeholder| {
        data = data ++ comptime .{ .{
            .placeholder = true,
            .value = "",
            .text = placeholder,
        }};
    }
    inline for (comptime std.enums.values(E)) |e| {
        data = data ++ comptime .{ .{
            .value = @tagName(e),
            .text = if (options.display_fn) |func| func(e) else @tagName(e),
        }};
    }
    try respond_with_options(req, data);
}

pub fn respond_with_options(req: *http.Request, options: []const Option) !void {
    _ = try req.maybe_add_response_header("content-type", http.content_type.json);
    try req.respond(try std.json.stringifyAlloc(http.temp(), options, .{
        .emit_null_optional_fields = false,
    }));
}

const tempora = @import("tempora");
const http = @import("http");
const std = @import("std");
