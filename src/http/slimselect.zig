pub const Option = struct {
    placeholder: ?bool = null,
    value: []const u8,
    text: []const u8,

    pub fn less_than(_: void, a: Option, b: Option) bool {
        const ap = a.placeholder orelse false;
        const bp = b.placeholder orelse false;
        if (ap != bp) {
            return ap;
        }
        return std.mem.lessThan(u8, a.text, b.text);
    }
};

pub fn Enum_Options(comptime E: type) type {
    return struct {
        placeholder: ?[]const u8 = null,
        display_fn: ?*const fn (e: E) []const u8 = null,
    };
}

pub fn respond_with_enum_options(req: *http.Request, comptime E: type, comptime options: Enum_Options(E)) !void {
    try req.add_response_header("content-type", http.content_type.json);
    try req.add_response_header("cache-control", "max-age=600, public");
    try req.check_and_add_last_modified(@import("root").resources.build_time);

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
