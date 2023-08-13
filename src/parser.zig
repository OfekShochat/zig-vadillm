const std = @import("std");
const Index = @import("ir.zig").Index;
const types = @import("types.zig");

const Parser = @This();

pub const Token = union(enum) {
    comment: []const u8,
    left_paren: void, // '('
    right_paren: void, // ')'
    left_brace: void, // '{'
    right_brace: void, // '}'
    left_bracket: void, // '['
    right_bracket: void, // ']'
    minus: void, // '-'
    plus: void, // '+'
    multiply: void, // '*'
    comma: void, // ','
    dot: void, // '.'
    colon: void, // ':'
    equal: void, // '='
    shebang: void, // '!'
    arrow: void, // '->'
    float: []const u8, // floating point immediate
    integer: []const u8, // integer immediate
    ty: types.Type, // i32, f32, b32x4, ...
    value: Index, // v12, v7
    block: Index, // block3
    global_value: Index, // gv3
    constant: Index, // const2
    ident: []const u8,
    string: []const u8, // "arbitrary quoted string with no escape" ...
    source_loc: []const u8, // @00c7
};

const NumberedEntity = struct {
    const Tag = enum {
        global_value,
        value,
    };

    tag: Tag,
    val: Index,
};

fn splitNumberedEntity(s: []const u8) !NumberedEntity {
    std.debug.assert(s.len > 0);

    if (std.mem.startsWith(u8, s, "gv")) {
        return NumberedEntity{
            .tag = .global_value,
            .val = try std.fmt.parseInt(Index, s[2..], 10),
        };
    } else if (s[0] == 'v') {
        return NumberedEntity{
            .tag = .value,
            .val = try std.fmt.parseInt(Index, s[1..], 10),
        };
    } else {
        return error.NotNumberedEntity;
    }
}

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    stream: []const u8,
    pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, stream: []const u8) Lexer {
        return Lexer{
            .allocator = allocator,
            .stream = stream,
        };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.stream.len and std.ascii.isWhitespace(self.stream[self.pos])) {
            self.pos += 1;
        }
    }

    fn scanSingleChar(self: *Lexer, token: Token) Token {
        std.debug.assert(self.pos < self.stream.len);
        self.pos += 1;
        return token;
    }

    fn scanIdent(self: *Lexer) !Token {
        std.debug.assert(self.stream[self.pos] == '_' or std.ascii.isAlphanumeric(self.stream[self.pos]));

        const start = self.pos;

        while (self.pos < self.stream.len) {
            switch (self.stream[self.pos]) {
                '_', '0'...'9', 'a'...'z', 'A'...'Z' => self.pos += 1,
                else => break,
            }
        }

        const numbered_entity = splitNumberedEntity(self.stream[start..self.pos]) catch return Token{ .ident = self.stream[start..self.pos] };
        return switch (numbered_entity.tag) {
            .global_value => Token{ .global_value = numbered_entity.val },
            .value => Token{ .value = numbered_entity.val },
        };
    }

    fn scanNumber(self: *Lexer) Token {
        const start = self.pos;
        var is_float = false;

        switch (self.stream[self.pos]) {
            '-' => {
                if (self.stream.len == self.pos + 1 or std.ascii.isAlphanumeric(self.stream[self.pos + 1])) {
                    return .minus;
                }
            },
            '+' => {
                if (self.stream.len == self.pos + 1 or std.ascii.isAlphanumeric(self.stream[self.pos + 1])) {
                    return .plus;
                }
            },
            else => {},
        }

        while (self.pos <= self.stream.len) {
            switch (self.stream[self.pos]) {
                '-', '_' => {},
                '.' => is_float = true,
                '0'...'9', 'a'...'z', 'A'...'Z' => {},
                else => break,
            }

            self.pos += 1;
        }

        const text = self.stream[start..self.pos];
        if (is_float) {
            return .{ .float = text };
        } else {
            return .{ .integer = text };
        }
    }

    fn lookingAt(self: *Lexer, p: []const u8) bool {
        return std.mem.startsWith(u8, self.stream, p);
    }

    pub fn next(self: *Lexer) !Token {
        if (self.pos >= self.stream.len) {
            return error.UnexpectedEOF;
        }

        self.skipWhitespace();

        return switch (self.stream[self.pos]) {
            '(' => return self.scanSingleChar(.left_paren),
            ')' => return self.scanSingleChar(.right_paren),
            '{' => return self.scanSingleChar(.left_brace),
            '}' => return self.scanSingleChar(.right_brace),
            '[' => return self.scanSingleChar(.left_bracket),
            ']' => return self.scanSingleChar(.right_bracket),
            '+' => return self.scanNumber(),
            '*' => return self.scanSingleChar(.multiply),
            ',' => return self.scanSingleChar(.comma),
            '.' => return self.scanSingleChar(.dot),
            ':' => return self.scanSingleChar(.colon),
            '=' => return self.scanSingleChar(.equal),
            '!' => return self.scanSingleChar(.shebang),
            '-' => {
                if (self.pos + 1 < self.stream.len and self.stream[self.pos + 1] == '>') {
                    // arrow `->`
                    self.pos += 2;
                    return .arrow;
                } else {
                    return self.scanNumber();
                }
            },
            ';' => {
                self.pos += 1;
                const start = self.pos;

                while (self.pos < self.stream.len and self.stream[self.pos] != '\n') {
                    self.pos += 1;
                }

                return .{ .comment = self.stream[start..self.pos] };
            },
            '"' => {
                self.pos += 1; // Skip the opening quote
                const start = self.pos;

                while (self.pos < self.stream.len and self.stream[self.pos] != '"') {
                    self.pos += 1;
                }

                // unterminated string literal
                if (self.stream[self.pos] != '"') {
                    return error.UnterminatedStringLiteral;
                }

                defer self.pos += 1;
                return .{ .string = self.stream[start..self.pos] };
            },
            '0'...'9' => self.scanNumber(),
            'a'...'z', 'A'...'Z' => {
                if (self.lookingAt("nan") or self.lookingAt("inf")) {
                    return self.scanNumber();
                } else {
                    return self.scanIdent();
                }
            },
            else => {
                return error.UnrecognizedChar;
            },
        };
    }
};

test "string literal" {
    var lexer = Lexer.init(std.testing.allocator, "\"hello boomer\"");
    const tok = try lexer.next();
    try std.testing.expectEqualStrings("hello boomer", tok.string);
}

test "comment" {
    var lexer = Lexer.init(std.testing.allocator, "; comment here");
    const tok = try lexer.next();
    try std.testing.expectEqualStrings(" comment here", tok.comment);
}

test "numbered entities" {
    var lexer = Lexer.init(std.testing.allocator, "v3");
    var tok = try lexer.next();
    try std.testing.expectEqual(@as(Index, 3), tok.value);

    lexer = Lexer.init(std.testing.allocator, "gv1337");
    tok = try lexer.next();
    try std.testing.expectEqual(@as(Index, 1337), tok.global_value);
}

test "idents" {
    var lexer = Lexer.init(std.testing.allocator, "vfad3");
    var tok = try lexer.next();
    try std.testing.expectEqualStrings("vfad3", tok.ident);
}
