const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

pub const Kind = enum {
    identifier,
    number_int,
    number_float,
    operator,
    keyword,
    delimiter,
};

pub const Lexed = struct {
    kind: Kind,
    content: []u8,

    const Self = @This();

    pub fn string(self: Self, alloc: Allocator) ![]u8 {
        const kindStr = kindString(self.kind);
        const len = kindStr.len;
        // +2 for ( and )
        var res = try alloc.alloc(u8, kindStr.len + 2 + self.content.len);
        for (0..len) |i| res[i] = kindStr[i];
        res[len] = '(';
        for (0..self.content.len) |i| res[i + len + 1] = self.content[i];
        res[res.len - 1] = ')';
        return res;
    }
};

fn kindString(kind: Kind) []const u8 {
    switch (kind) {
        .identifier => return "identifier",
        .number_int => return "number_int",
        .number_float => return "number_float",
        .operator => return "operator",
        .keyword => return "keyword",
        .delimiter => return "delimiter",
    }
}

fn stringEq(s1: []u8, s2: []u8) bool {
    if (s1.len != s2.len) return false;
    for (0..s1.len) |i| {
        if (s1[i] != s2[i]) return false;
    }
    return true;
}

fn constToVar(alloc: Allocator, to: [:0]const u8) ![]u8 {
    var res = try alloc.alloc(u8, to.len);
    for (0..to.len) |i| res[i] = to[i];
    return res;
}

test "lexed string" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const array: [:0]const u8 = "12";
    const l = Lexed{ .kind = Kind.number_int, .content = try constToVar(allocator, array) };
    const expected: [:0]const u8 = "number_int(12)";
    try expect(stringEq(try l.string(allocator), try constToVar(allocator, expected)));
}
