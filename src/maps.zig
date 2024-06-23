pub fn String_Hash_Map_Ignore_Case(comptime V: type) type {
    return std.HashMap([]const u8, V, String_Context_Ignore_Case, std.hash_map.default_max_load_percentage);
}

pub fn String_Hash_Map_Ignore_Case_Unmanaged(comptime V: type) type {
    return std.HashMapUnmanaged([]const u8, V, String_Context_Ignore_Case, std.hash_map.default_max_load_percentage);
}

pub fn Qualified_String_Hash_Map_Ignore_Case(comptime NS: type, comptime V: type) type {
    const K = struct { NS, []const u8 };
    return std.HashMap(K, V, Qualified_String_Context_Ignore_Case(K), std.hash_map.default_max_load_percentage);
}

pub fn Qualified_String_Hash_Map_Ignore_Case_Unmanaged(comptime NS: type, comptime V: type) type {
    const K = struct { NS, []const u8 };
    return std.HashMapUnmanaged(K, V, Qualified_String_Context_Ignore_Case(K), std.hash_map.default_max_load_percentage);
}


pub const String_Context_Ignore_Case = struct {
    pub fn hash(self: @This(), s: []const u8) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        hash_string_ignore_case(&h, s);
        return h.final();
    }
    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        return std.ascii.eqlIgnoreCase(a, b);
    }
};

pub fn Qualified_String_Context_Ignore_Case(comptime K: type) type {
    return struct {
        pub fn hash(self: @This(), k: K) u64 {
            _ = self;
            var h = std.hash.Wyhash.init(0);
            std.hash.autoHash(&h, k.@"0");
            hash_string_ignore_case(&h, k.@"1");
            return h.final();
        }
        pub fn eql(self: @This(), a: K, b: K) bool {
            _ = self;
            return std.meta.eql(a.@"0", b.@"0") and std.ascii.eqlIgnoreCase(a.@"1", b.@"1");
        }
    };
}

pub fn hash_string_ignore_case(hash: *std.hash.Wyhash, s: []const u8) void {
    var buf: [64]u8 = undefined;
    var remaining = s;
    while (remaining.len > buf.len) {
        hash.update(std.ascii.lowerString(&buf, remaining[0..buf.len]));
        remaining = remaining[buf.len..];
    }
    hash.update(std.ascii.lowerString(&buf, remaining));
}

const std = @import("std");
