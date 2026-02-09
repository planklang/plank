const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Kind = enum {
    identifier,
    number_int,
    number_float,
    operator,
    keyword,
    delimiter,
};

pub const Lexed = struct {
    allocator: Allocator,
    kind: Kind,
    content: std.ArrayList(u8),

    const Self = @This();

    pub fn init(alloc: Allocator, kind: Kind, content: std.ArrayList(u8)) Lexed {
        return Lexed{
            .allocator = alloc,
            .kind = kind,
            .content = content,
        };
    }

    pub fn deinit(self: *Self) void {
        self.content.deinit(self.allocator);
    }

    pub fn string(self: Self, alloc: Allocator) Allocator.Error![]u8 {
        const kind_str = kind_string(self.kind);
        const kind_len = kind_str.len;
        const content_len = self.content.items.len;
        // +2 for ( and )
        var res = try alloc.alloc(u8, kind_len + 2 + content_len);
        for (0..kind_len) |i| res[i] = kind_str[i];
        res[kind_len] = '(';
        for (0..content_len) |i| res[i + kind_len + 1] = self.content.items[i];
        res[res.len - 1] = ')';
        return res;
    }

    pub fn equals(self: *Self, kind: Kind, content: anytype) bool {
        if (kind != self.kind) return false;
        var items = content;
        switch (@TypeOf(content)) {
            std.ArrayList(u8), *std.ArrayList(u8) => items = content.items,
            else => {},
        }
        return std.mem.eql(u8, self.content.items, items);
    }
};

pub fn kind_string(kind: Kind) []const u8 {
    switch (kind) {
        .identifier => return "identifier",
        .number_int => return "number_int",
        .number_float => return "number_float",
        .operator => return "operator",
        .keyword => return "keyword",
        .delimiter => return "delimiter",
    }
}

test "lexed string" {
    const expect = std.testing.expect;

    var arena = std.heap.DebugAllocator(.{}){};
    defer {
        switch (arena.deinit()) {
            .leak => std.debug.print("memory leak", .{}),
            .ok => {},
        }
    }
    const alloc = arena.allocator();

    var content = try std.ArrayList(u8).initCapacity(alloc, 2);
    try content.appendSlice(alloc, "12");

    var l = Lexed.init(alloc, Kind.number_int, content);
    defer l.deinit();

    try expect(l.equals(.number_int, "12"));
}
