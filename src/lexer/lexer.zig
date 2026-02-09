const std = @import("std");
const Allocator = std.mem.Allocator;
const lexed = @import("lexed.zig");

const operators = [_][]const u8{ "+", "-", "*", "/", "=", ">", "<", "!=", "(", ")" };
const delimiters = [_][]const u8{ "\n", ";;", "|", ":", "->" };
const keywords = [_][]const u8{ "let", "when" };

pub const LexError = error{
    /// Sequence is composed by valid chars, but its form is invalid
    InvalidSequence,
    /// Char is unknown
    UnknownChar,
};

pub const LexerError = Allocator.Error || LexError;

fn is_in(arr: []const []const u8, v: anytype) bool {
    switch (@TypeOf(v)) {
        u8 => for (arr) |it| if (it[0] == v) return true,
        []u8 => for (arr) |it| if (std.mem.eql(u8, it, v)) return true,
        else => unreachable,
    }
    return false;
}

fn is_operator(v: anytype) bool {
    return is_in(&operators, v);
}

fn is_delimiter(v: anytype) bool {
    return is_in(&delimiters, v);
}

fn is_keyword(v: anytype) bool {
    return is_in(&keywords, v);
}

fn is_identifier_char(v: u8) bool {
    if (v > 'z') return false;
    if (v > 'Z' and v != '_' and v < 'a') return false;
    if (v < 'A') return false;
    return true;
}

fn is_identifier(v: []u8) bool {
    for (v, 0..) |it, i| {
        if (i == 0 and v == '_') return false;
        if (!is_identifier_char(it)) return false;
    }
    return true;
}

fn is_number(v: u8) bool {
    return v <= '9' and v >= '0' or v == '_';
}

fn is_number_int(v: []u8) bool {
    for (v) |it| if (!is_number(it)) return false;
    return true;
}

fn is_number_float(v: []u8) bool {
    var point = false;
    for (v) |it| {
        if (it == '.') {
            if (point) return false;
            point = true;
        } else if (!is_number(it)) {
            return false;
        }
    }
    return true;
}

pub const Lexer = struct {
    alloc: Allocator,
    content: std.ArrayList(*lexed.Lexed),

    const Self = @This();

    pub fn init(alloc: Allocator) Allocator.Error!Lexer {
        return Lexer{ .alloc = alloc, .content = try std.ArrayList(*lexed.Lexed).initCapacity(alloc, 2) };
    }

    pub fn deinit(self: *Self) void {
        for (self.content.items) |it| {
            it.deinit();
            self.alloc.destroy(it);
        }
        self.content.deinit(self.alloc);
    }

    pub fn append(self: *Self, lx: lexed.Lexed) Allocator.Error!void {
        const l = try self.alloc.create(lexed.Lexed);
        l.* = lx;
        try self.content.append(self.alloc, l);
    }

    pub fn appendCreate(self: *Self, kind: lexed.Kind, acc: std.ArrayList(u8)) Allocator.Error!void {
        try self.append(lexed.Lexed.init(self.alloc, kind, acc));
    }
};

fn get_current_kind(it: u8) LexError!lexed.Kind {
    if (it == '.') {
        return .number_float;
    } else if (is_number(it)) {
        return .number_int;
    } else if (is_operator(it)) {
        return .operator;
    } else if (is_identifier_char(it)) {
        if (is_keyword(it)) return .keyword;
        return .identifier;
    } else if (is_delimiter(it)) {
        return .delimiter;
    } else {
        return LexError.UnknownChar;
    }
}

fn append(alloc: Allocator, lexer: *Lexer, kind: lexed.Kind, acc: *std.ArrayList(u8), current: ?u8) LexerError!?lexed.Kind {
    try lexer.appendCreate(kind, acc.*);
    acc.* = try std.ArrayList(u8).initCapacity(alloc, 2);
    const it = current orelse return null;
    return try get_current_kind(it);
}

pub fn lex(alloc: Allocator, content: []u8) LexerError!Lexer {
    var lexer = try Lexer.init(alloc);
    errdefer lexer.deinit();

    var acc = try std.ArrayList(u8).initCapacity(alloc, 2);
    defer acc.deinit(alloc);

    var current_kind = lexed.Kind.identifier;

    for (content) |it| {
        const size = acc.items.len;
        if (it == ' ') {
            if (size > 0) _ = try append(alloc, &lexer, current_kind, &acc, null);
            continue;
        }
        if (size > 0) {
            var next = try acc.clone(alloc);
            defer next.deinit(alloc);
            try next.append(alloc, it);

            switch (current_kind) {
                .delimiter => {
                    if (!is_delimiter(it)) {
                        current_kind = (try append(alloc, &lexer, current_kind, &acc, it)).?;
                    } else if (!is_delimiter(next.items)) return LexError.InvalidSequence;
                },
                .identifier => {
                    if (!is_identifier_char(it) and (it != '_' or size == 0)) {
                        current_kind = (try append(alloc, &lexer, current_kind, &acc, it)).?;
                    } else if (is_keyword(next.items)) {
                        current_kind = .keyword;
                    }
                },
                .keyword => {
                    if (!is_keyword(next.items)) {
                        if (is_identifier_char(it)) {
                            current_kind = .identifier;
                        } else {
                            current_kind = (try append(alloc, &lexer, current_kind, &acc, it)).?;
                        }
                    }
                },
                .operator => {
                    if (!is_operator(it)) {
                        current_kind = (try append(alloc, &lexer, current_kind, &acc, it)).?;
                    } else if (!is_operator(next.items)) return LexError.InvalidSequence;
                },
                .number_int => {
                    if (!is_number(it) and it != '.') {
                        current_kind = (try append(alloc, &lexer, current_kind, &acc, it)).?;
                    } else if (!is_number_int(next.items)) {
                        if (is_number_float(next.items)) {
                            current_kind = .number_float;
                        } else {
                            return LexError.InvalidSequence;
                        }
                    }
                },
                .number_float => {
                    if (!is_number_float(next.items)) {
                        if (it == '.') return LexError.InvalidSequence;
                        current_kind = (try append(alloc, &lexer, current_kind, &acc, it)).?;
                    }
                },
            }
        } else {
            current_kind = try get_current_kind(it);
        }
        try acc.append(alloc, it);
    }
    if (acc.items.len > 0) {
        _ = try append(alloc, &lexer, current_kind, &acc, null);
    }

    return lexer;
}

test "lexer string" {
    const expect = std.testing.expect;

    var arena = std.heap.DebugAllocator(.{}){};
    defer _ = arena.deinit();
    const alloc = arena.allocator();

    const input: [:0]const u8 = "12+ x*1_2.5";
    const input_var = try lexed.test_const_to_var(alloc, input);
    defer alloc.free(input_var);
    var l = try lex(alloc, input_var);
    defer l.deinit();

    try expect(l.content.items[0].equals(.number_int, "12"));
    try expect(l.content.items[1].equals(.operator, "+"));
    try expect(l.content.items[2].equals(.identifier, "x"));
    try expect(l.content.items[3].equals(.operator, "*"));
    try expect(l.content.items[4].equals(.number_float, "1_2.5"));
}

test "lexer errors" {
    var arena = std.heap.DebugAllocator(.{}){};
    defer _ = arena.deinit();
    const alloc = arena.allocator();

    const input: [:0]const u8 = "1.2.";
    const input_var = try lexed.test_const_to_var(alloc, input);
    defer alloc.free(input_var);

    _ = lex(alloc, input_var) catch |err| switch (err) {
        LexerError.InvalidSequence => {
            const input2: [:0]const u8 = "hey œ :D";
            const input2_var = try lexed.test_const_to_var(alloc, input2);
            defer alloc.free(input2_var);

            _ = lex(alloc, input2_var) catch |err2| switch (err2) {
                LexerError.UnknownChar => return,
                else => return err2,
            };
            unreachable;
        },
        else => return err,
    };
    unreachable;
}
