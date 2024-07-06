pub fn validate_opt_datetime_local(data: *Field_Data, tz: ?*const tempora.Timezone) !bool {
    if (data.future.len == 0) return true;

    _ = parse_opt_datetime_local(data.future, tz) catch {
        data.err = try http.tprint("'{s}' is not a valid timestamp!", .{ data.future });
        data.valid = false;
        return false;
    };

    return true;
}

pub fn parse_opt_datetime_local(str: []const u8, tz: ?*const tempora.Timezone) !?i64 {
    if (str.len == 0) return null;

    const dto = try DTO.from_string_tz(fmt_datetime_local, str, tz);
    return dto.timestamp_ms();
}

pub fn format_opt_datetime_local(maybe_ts: ?i64, tz: ?*const tempora.Timezone) ![]const u8 {
    if (maybe_ts) |ts| {
        const dto = DTO.from_timestamp_ms(ts, tz);
        return try http.tprint(datetime_local, .{ dto });
    }
    return "";
}

const DTO = tempora.Date_Time.With_Offset;

const fmt_datetime_local = "YYYY-MM-DDTHH;mm";
const datetime_local = "{" ++ fmt_datetime_local ++ "}";

const Field_Data = @import("Field_Data.zig");
const http = @import("http");
const tempora = @import("tempora");
const std = @import("std");
