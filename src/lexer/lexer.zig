const std = @import("std");
const Allocator = std.mem.Allocator;
const lexed = @import("lexed.zig");

const operators = [_][]const u8{ "+", "-", "*", "/", "=", ">", "<", "!=", "(", ")" };
const delimiters = [_][]const u8{ "\n", ";;", "|", ":", "->" };
const keywords = [_][]const u8{ "let", "when" };

pub const LexerError = error{
    InvalidSequence,
    UnknownChar,
};

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

fn append(alloc: Allocator, lexeds: *std.ArrayList(*lexed.Lexed), kind: lexed.Kind, acc: *std.ArrayList(u8)) Allocator.Error!void {
    const lx = try lexed.Lexed.init(alloc, kind, acc.*);
    try lexeds.append(alloc, lx);
    acc.* = try std.ArrayList(u8).initCapacity(alloc, 2);
}

fn get_current_kind(it: u8) !lexed.Kind {
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
        return LexerError.UnknownChar;
    }
}

pub fn lex(alloc: Allocator, content: []u8) !std.ArrayList(*lexed.Lexed) {
    var lexeds = try std.ArrayList(*lexed.Lexed).initCapacity(alloc, 2);
    errdefer {
        for (lexeds.items) |it| {
            it.deinit();
            alloc.destroy(it);
        }
        lexeds.deinit(alloc);
    }

    var acc = try std.ArrayList(u8).initCapacity(alloc, 2);
    defer acc.deinit(alloc);

    var current_kind = lexed.Kind.identifier;
    for (content) |it| {
        const size = acc.items.len;
        if (it == ' ') {
            if (size > 0) try append(alloc, &lexeds, current_kind, &acc);
            continue;
        }
        if (size > 0) {
            var next = try acc.clone(alloc);
            defer next.deinit(alloc);
            try next.append(alloc, it);

            switch (current_kind) {
                .delimiter => {
                    if (!is_delimiter(it)) {
                        try append(alloc, &lexeds, current_kind, &acc);
                        current_kind = try get_current_kind(it);
                    } else if (!is_delimiter(next.items)) return LexerError.InvalidSequence;
                },
                .identifier => {
                    if (!is_identifier_char(it) and (it != '_' or size == 0)) {
                        try append(alloc, &lexeds, current_kind, &acc);
                        current_kind = try get_current_kind(it);
                    } else if (is_keyword(next.items)) {
                        current_kind = .keyword;
                    }
                },
                .keyword => {
                    if (!is_keyword(next.items)) {
                        if (is_identifier_char(it)) {
                            current_kind = .identifier;
                        } else {
                            try append(alloc, &lexeds, current_kind, &acc);
                            current_kind = try get_current_kind(it);
                        }
                    }
                },
                .operator => {
                    if (!is_operator(it)) {
                        try append(alloc, &lexeds, current_kind, &acc);
                        current_kind = try get_current_kind(it);
                    } else if (!is_operator(next.items)) return LexerError.InvalidSequence;
                },
                .number_int => {
                    if (!is_number(it) and it != '.') {
                        try append(alloc, &lexeds, current_kind, &acc);
                        current_kind = try get_current_kind(it);
                    } else if (!is_number_int(next.items)) {
                        if (is_number_float(next.items)) {
                            current_kind = .number_float;
                        } else {
                            return LexerError.InvalidSequence;
                        }
                    }
                },
                .number_float => {
                    if (!is_number_float(next.items)) {
                        if (it == '.') return LexerError.InvalidSequence;
                        try append(alloc, &lexeds, current_kind, &acc);
                        current_kind = try get_current_kind(it);
                    }
                },
            }
        } else {
            current_kind = try get_current_kind(it);
        }
        try acc.append(alloc, it);
    }
    if (acc.items.len > 0) try append(alloc, &lexeds, current_kind, &acc);

    return lexeds;
}

test "lexer string" {
    const expect = std.testing.expect;

    var arena = std.heap.DebugAllocator(.{}){};
    defer _ = arena.deinit(); 
    const alloc = arena.allocator();

    const input: [:0]const u8 = "12+ x*1_2.5";
    const input_var = try lexed.test_const_to_var(alloc, input);
    defer alloc.free(input_var);
    var val = try lex(alloc, input_var);
    defer {
        for (val.items) |it| {
            it.deinit();
            alloc.destroy(it);
        }
        val.deinit(alloc);
    }

    try expect(val.items[0].equalsStatic(.number_int, "12"));
    try expect(val.items[1].equalsStatic(.operator, "+"));
    try expect(val.items[2].equalsStatic(.identifier, "x"));
    try expect(val.items[3].equalsStatic(.operator, "*"));
    try expect(val.items[4].equalsStatic(.number_float, "1_2.5"));
}
