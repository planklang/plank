const std = @import("std");
const Allocator = std.mem.Allocator;
const lexed = @import("lexed.zig");

const operators = [_][]u8{"+", "-", "*", "/", "=", ">", "<", "!=", "(", ")"};
const delimiters = [_][]u8{"\n", ";;", "|", ":", "->"};
const keywords = [_][]u8{"let", "when"};

fn str_eq(s1: []u8, s2: []u8) bool {
    if (s1.len != s2.len) return false;
    for (0..s1.len) |i| {
        if (s1[i] != s2[i]) return false;
    }
    return true;
}

fn is_operator(v: []u8) bool {
    for (operators) |it| {
        if (str_eq(it, v)) return true;
    }
    return false;
}

fn is_delimiters(v: []u8) bool {
    for (delimiters) |it| {
        if (str_eq(it, v)) return true;
    }
    return false;
}

fn is_keywords(v: []u8) bool {
    for (keywords) |it| {
        if (str_eq(it, v)) return true;
    }
    return false;
}

fn is_identifier(v: []u8) bool {
    for (v, 0..) |it, i| {
        if (i == 0 and v == '_') return false;
        if (it > 'z') return false;
        if (it > 'Z' and it != '_' and it < 'a') return false;
        if (it < 'A') return false;
    }
    return true;
}

fn is_number(v: u8) bool {
    return v <= '9' and v >= '0';
}

fn is_number_int(v: []u8) bool {
    for (v) |it| {
        if (!is_number(it)) return false;
    }
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

fn append(T: type, allocator: Allocator, items: *[]T, n: *usize, item: T) !void {
    if (items.len == *n) items.* = try allocator.realloc(items, items.len*2);
    items[n] = item;
    n.* += 1;
}

fn append_lex(allocator: Allocator, lexeds: *[]lexed.Lexed, n: *usize, kind: lexed.Kind, acc: *[]u8) !void {
    const lx = lexed.Lexed{.content = acc.*, .kind = kind};
    try append(lexed.Lexed, allocator, lexeds, n, lx);
    acc.* = try allocator.alloc(u8, 1);
}

fn update(allocator: Allocator, lexeds: *[]lexed.Lexed, n: *usize, acc: *[]u8) !void {
    // determined sequence
    if (is_operator(acc)) {
        try append_lex(allocator, &lexeds, &n, lexed.Kind.operator, acc);
        return;
    } else if (is_delimiters(acc)) {
        try append_lex(allocator, &lexeds, &n, lexed.Kind.delimiter, acc);
        return;
    }
    // indetermined sequence
}

pub fn lex(allocator: Allocator, content: []u8) ![]lexed.Lexed {
    var n: usize = 0;
    var lexeds = try allocator.alloc(lexed.Lexed, 2);

    var size: usize = 0;
    var acc = try allocator.alloc(u8, 2);
    for (content) |it| {
        try append(u8, allocator, &acc, &size, it);
        update(allocator, lexeds, &n, &acc[0..size]);
    }

    return lexeds[0..n];
}
