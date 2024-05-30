
pub fn lexicographic(data: [][]const u8) void {
    std.sort.block([]const u8, data, {}, lexicographic_less_than);
}

pub fn lexicographic_less_than(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn natural(data: [][]const u8) void {
    std.sort.block([]const u8, data, {}, natural_less_than);
}

pub fn natural_less_than(_: void, a: []const u8, b: []const u8) bool {
    var ai: usize = 0;
    var bi: usize = 0;
    next_byte: while (ai < a.len and bi < b.len) {
        var ac = a[ai];
        var bc = b[bi];

        { // case insensitive alpha ordering:
            const aca = std.ascii.isAlphabetic(ac);
            const bca = std.ascii.isAlphabetic(bc);

            if (aca and bca) {
                const acl = std.ascii.toLower(ac);
                const bcl = std.ascii.toLower(bc);
                if (acl != bcl) return acl < bcl;
                ai += 1;
                bi += 1;
                continue :next_byte;
            }

            if (aca) return false;
            if (bca) return true;
        }

        const acd = std.ascii.isDigit(ac);
        const bcd = std.ascii.isDigit(bc);

        if (acd and bcd) {
            // skip any leading zeroes
            while (ac == '0' and ai + 1 < a.len and std.ascii.isDigit(a[ai + 1])) {
                ai += 1;
                ac = a[ai];
            }
            while (bc == '0' and bi + 1 < b.len and std.ascii.isDigit(b[bi + 1])) {
                bi += 1;
                bc = b[bi];
            }

            var same_length_result: ?bool = null;
            if (ac != bc) same_length_result = ac < bc;

            const ar = a[ai..];
            const br = b[bi..];
            const rlen = @min(ar.len, br.len);

            for (1.., ar[1..rlen], br[1..rlen]) |n, acn, bcn| {
                const acnd = std.ascii.isDigit(acn);
                const bcnd = std.ascii.isDigit(bcn);

                if (acnd != bcnd) {
                    return bcnd;
                } else if (acnd) {
                    // both digits continue their respective numbers; set same_length_result if it's still null:
                    if (same_length_result == null and acn != bcn) {
                        same_length_result = acn < bcn;
                    }
                } else {
                    // neither digit is a number; numeric sequences are the same length
                    if (same_length_result) |result| return result;
                    ai += n;
                    bi += n;
                    continue :next_byte;
                }
            }

            // we reached the end of one or both strings, but one may have a number still continuing:
            if (ar.len > rlen) {
                if (std.ascii.isDigit(ar[rlen])) return false;
            } else if (br.len > rlen) {
                if (std.ascii.isDigit(br[rlen])) return true;
            }

            // both numbers were the same length
            if (same_length_result) |result| return result;
            
            // both numbers were identical and ran until the end of one or both strings.  Skip to the end.
            ai += rlen;
            bi += rlen;
            break :next_byte;
        }

        if (acd) return false;
        if (bcd) return true;

        if (ac != bc) return ac < bc;

        ai += 1;
        bi += 1;
    }

    return bi < b.len;
}

test natural_less_than {
    try natural_eql_test("", "");
    try natural_eql_test("a", "a");
    try natural_eql_test("a100", "a100");
    try natural_eql_test("A", "a");
    try natural_eql_test("SOMETHING", "SOMEthing");
    try natural_eql_test("0", "00000");
    try natural_eql_test("0a", "00000a");
    try natural_eql_test("1", "00001");
    try natural_eql_test("99AA", "99aa");
    try natural_less_than_test("A", "AA");
    try natural_less_than_test("A", "B");
    try natural_less_than_test("A", "b");
    try natural_less_than_test("a", "B");
    try natural_less_than_test("a", "b");
    try natural_less_than_test("!", "~");
    try natural_less_than_test("~", "A");
    try natural_less_than_test("~", "b");
    try natural_less_than_test("~", "0");
    try natural_less_than_test(">", "0");
    try natural_less_than_test("0", "A");
    try natural_less_than_test("0", "a");
    try natural_less_than_test("0", "1");
    try natural_less_than_test("5", "6");
    try natural_less_than_test("3", "9");
    try natural_less_than_test("9", "10");
    try natural_less_than_test("9998", "9999");
    try natural_less_than_test("9999", "99999");
    try natural_less_than_test("9999a", "99999");
    try natural_less_than_test("9999", "11111");
    try natural_less_than_test("01111", "9999");
    try natural_less_than_test("00001", "099");
    try natural_less_than_test("00001", "000000000000099");
    try natural_less_than_test("00000000a", "000b");
    try natural_less_than_test("00000000", "000b");
    try natural_less_than_test("9999aaaa", "99999aaa");
    try natural_less_than_test("9999aaaa", "99999AAA");
    try natural_less_than_test("99AA0", "99aa1");
    try natural_less_than_test("9.9", "9.10");
}

fn natural_less_than_test(smaller: []const u8, larger: []const u8) !void {
    try std.testing.expect(natural_less_than({}, smaller, larger));
    try std.testing.expect(!natural_less_than({}, larger, smaller));
}

fn natural_eql_test(a: []const u8, b: []const u8) !void {
    try std.testing.expect(!natural_less_than({}, a, b));
    try std.testing.expect(!natural_less_than({}, b, a));
}

const std = @import("std");
