// Used by Transaction structs to represent each individually editable piece of data that might be changing.
const Field_Data = @This();

current: []const u8 = "",
future: []const u8 = "",
processed: bool = false,
valid: bool = true,
err: []const u8 = "",

pub fn init(db: *const DB, val: anytype) !Field_Data {
    if (@TypeOf(val) == Field_Data) return val;
    const str = try value_to_str(db, val);
    return .{
        .current = str,
        .future = str,
    };
}

fn value_to_str(db: *const DB, val: anytype) ![]const u8 {
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .Enum => if (comptime @hasDecl(T, "Type") and std.mem.endsWith(u8, @typeName(T), ".Index")) db.get_id(val) else @tagName(val),
        .EnumLiteral => @tagName(val),
        .Float, .Int => try http.tprint("{d}", .{ val }),
        .ComptimeFloat, .ComptimeInt => std.fmt.comptimePrint("{d}", .{ val }),
        .Null => "",
        .Optional => if (val) |v| value_to_str(db, v) else "",
        .Pointer => |info| if (info.size == .Slice) val else value_to_str(db, val.*),
        else => @compileError("Invalid data type for Field_Data: " ++ @typeName(T)),
    };
}

pub fn init_fields(comptime F: type, db: *const DB, data: anytype) !std.enums.EnumFieldStruct(F, Field_Data, null) {
    @setEvalBranchQuota(2 * @typeInfo(F).Enum.fields.len);
    var result: std.enums.EnumFieldStruct(F, Field_Data, null) = undefined;
    inline for (@typeInfo(F).Enum.fields) |field| {
        @field(result, field.name) = try init(db, @field(data, field.name));
    }
    return result;
}

pub fn init_fields_ext(comptime F: type, db: *const DB, data: anytype, overrides: anytype) !std.enums.EnumFieldStruct(F, Field_Data, null) {
    @setEvalBranchQuota(2 * @typeInfo(F).Enum.fields.len);
    var result: std.enums.EnumFieldStruct(F, Field_Data, null) = undefined;
    inline for (@typeInfo(F).Enum.fields) |field| {
        if (@hasField(@TypeOf(overrides), field.name)) {
            @field(result, field.name) = try init(db, @field(overrides, field.name));
        } else {
            @field(result, field.name) = try init(db, @field(data, field.name));
        }
    }
    return result;
}

pub fn future_obj(comptime F: type, fields: std.enums.EnumFieldStruct(F, Field_Data, null)) std.enums.EnumFieldStruct(F, []const u8, null) {
    @setEvalBranchQuota(2 * @typeInfo(F).Enum.fields.len);
    var result: std.enums.EnumFieldStruct(F, []const u8, null) = undefined;
    inline for (@typeInfo(F).Enum.fields) |field| {
        @field(result, field.name) = @field(fields, field.name).future;
    }
    return result;
}

pub fn set_processed(self: *Field_Data, value: []const u8, also_set_current: bool) void {
    self.future = value;
    if (also_set_current) {
        self.current = value;
    }
    self.processed = true;
}

pub fn is_changed(self: Field_Data) bool {
    return !std.mem.eql(u8, self.current, self.future);
}
pub fn changed(self: Field_Data) ?Field_Data {
    return if (self.is_changed()) self else null;
}

pub fn is_edited(self: Field_Data) bool {
    return self.is_changed() and !self.is_added() and !self.is_removed();
}
pub fn edited(self: Field_Data) ?Field_Data {
    return if (self.is_edited()) self else null;
}

pub fn is_added(self: Field_Data) bool {
    return self.current.len == 0 and self.future.len > 0;
}
pub fn added(self: Field_Data) ?Field_Data {
    return if (self.is_added()) self else null;
}

pub fn is_removed(self: Field_Data) bool {
    return self.current.len > 0 and self.future.len == 0;
}

pub fn current_opt(self: Field_Data) ?[]const u8 {
    return if (self.current.len == 0) null else self.current;
}

pub fn future_opt(self: Field_Data) ?[]const u8 {
    return if (self.future.len == 0) null else self.future;
}

pub fn current_int(self: Field_Data, comptime T: type) T {
    return std.fmt.parseInt(T, self.current, 10) catch unreachable;
}

pub fn future_int(self: Field_Data, comptime T: type) T {
    return std.fmt.parseInt(T, self.future, 10) catch unreachable;
}

pub fn current_opt_int(self: Field_Data, comptime T: type) ?T {
    if (self.current.len == 0) return null;
    return self.current_int(T);
}

pub fn future_opt_int(self: Field_Data, comptime T: type) ?T {
    if (self.future.len == 0) return null;
    return self.future_int(T);
}

pub fn current_enum(self: Field_Data, comptime T: type) T {
    return std.meta.stringToEnum(T, self.current).?;
}

pub fn future_enum(self: Field_Data, comptime T: type) T {
    return std.meta.stringToEnum(T, self.future).?;
}

pub fn current_opt_enum(self: Field_Data, comptime T: type) ?T {
    if (self.current.len == 0) return null;
    return self.current_enum(T);
}

pub fn future_opt_enum(self: Field_Data, comptime T: type) ?T {
    if (self.future.len == 0) return null;
    return self.future_enum(T);
}

const DB = @import("../DB.zig");
const http = @import("http");
const std = @import("std");
