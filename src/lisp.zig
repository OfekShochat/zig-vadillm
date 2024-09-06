const std = @import("std");

pub const SourceLoc = struct {
    line: usize = 1,
    char: usize = 1,
};

pub const Immediate = union(enum) {
    float: []const u8,
    integer: []const u8,
};

pub const Scope = struct {
    params: std.ArrayListUnmanaged(Node) = .{},

    pub fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        for (self.params.items) |*param| {
            param.deinit(allocator);
        }

        self.params.deinit(allocator);
    }
};

pub const Node = union(enum) {
    imm: Immediate,
    name: []const u8,
    intrinsic: []const u8,
    scope: Scope,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .scope => |*scope| scope.deinit(allocator),
            else => {},
        }
    }
};

const Token = struct {
    start: SourceLoc,
    end: SourceLoc,
    data: Data,

    pub const Data = union(enum) {
        immediate: Immediate,
        intrinsic: []const u8,
        name: []const u8,
        scope_start: void,
        scope_end: void,
    };
};

const Lexer = struct {
    source: []const u8,
    position: usize = 0,

    source_loc: SourceLoc = .{},

    pub fn nextToken(self: *Lexer) ?Token {
        if (self.position >= self.source.len) {
            return null;
        }

        const start = self.source_loc;

        const curr = self.source[self.position];
        const token_data: Token.Data = switch (curr) {
            '(' => blk: {
                self.position += 1;
                break :blk .scope_start;
            },
            ')' => blk: {
                self.position += 1;
                break :blk .scope_end;
            },
            ':' => blk: {
                self.position += 1;
                break :blk .{ .intrinsic = self.scanName() };
            },
            '0'...'9', '-', '+' => blk: {
                if (self.scanImmediate()) |imm| {
                    break :blk .{ .immediate = imm };
                } else {
                    return null;
                }
            },
            ' ' => {
                self.position += 1;
                return self.nextToken();
            },
            '\n' => {
                self.position += 1;
                self.source_loc.line += 1;
                self.source_loc.char = 1;
                return self.nextToken();
            },
            else => .{ .name = self.scanName() },
        };

        return Token{ .start = start, .end = self.source_loc, .data = token_data };
    }

    fn scanName(self: *Lexer) []const u8 {
        const start = self.position;

        while (self.position < self.source.len) {
            switch (self.source[self.position]) {
                ' ', '(', ')', '\n' => break,
                else => self.position += 1,
            }
        }

        return self.source[start..self.position];
    }

    fn scanImmediate(self: *Lexer) ?Immediate {
        const start = self.position;
        var is_float = false;

        switch (self.source[self.position]) {
            '-' => {
                if (self.source.len == self.position + 1 or std.ascii.isAlphanumeric(self.source[self.position + 1])) {
                    return null; //.minus;
                }
            },
            '+' => {
                if (self.source.len == self.position + 1 or std.ascii.isAlphanumeric(self.source[self.position + 1])) {
                    return null; //.plus;
                }
            },
            else => {},
        }

        while (self.position <= self.source.len) {
            switch (self.source[self.position]) {
                '-', '_' => {},
                '.' => is_float = true,
                '0'...'9', 'a'...'z', 'A'...'Z' => {},
                else => break,
            }

            self.position += 1;
        }

        const text = self.source[start..self.position];
        if (is_float) {
            return .{ .float = text };
        } else {
            return .{ .integer = text };
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Scope {
    var lexer = Lexer{ .source = source };
    var scope_stack = std.ArrayList(Scope).init(allocator);

    defer scope_stack.deinit();
    errdefer {
        for (scope_stack.items) |*scope| {
            scope.deinit(allocator);
        }
    }

    try scope_stack.append(Scope{}); // root scope

    var level: usize = 0;

    while (lexer.nextToken()) |token| {
        var params = &scope_stack.items[scope_stack.items.len - 1].params;

        switch (token.data) {
            .scope_start => {
                level += 1;
                try scope_stack.append(Scope{});
            },
            .scope_end => {
                if (level == 0) return error.BadLevels;
                level -= 1;

                const curr_scope = scope_stack.pop();
                try scope_stack.items[scope_stack.items.len - 1].params.append(allocator, .{ .scope = curr_scope });
            },
            .immediate => |imm| try params.append(allocator, .{ .imm = imm }),
            .intrinsic => |intrinsic| try params.append(allocator, .{ .intrinsic = intrinsic }),
            .name => |name| try params.append(allocator, .{ .name = name }),
        }
    }

    if (level != 0) {
        return error.UnclosedScope;
    }

    return scope_stack.getLast();
}

test "lisp" {
    const source =
        \\(:def hello-adam3 int
        \\    (add arg0 arg1))
        \\
        \\(:def hello-adam2 int
        \\    (add arg0 10))
        \\
    ;
    var scope = try parse(std.testing.allocator, source);
    defer scope.deinit(std.testing.allocator);

    // try std.testing.expectEqualSlices(Node, &.{
    //     .{ .intrinsic = "def" },
    //     .{ .name = "hello-adam3" },
    //     .{ .name = "int" },
    // }, scope.params.items[0].scope.params.items[0..3]);

    // try std.testing.expectEqualSlices(Node, &.{
    //     .{ .intrinsic = "def" },
    //     .{ .name = "hello-adam2" },
    //     .{ .name = "int" },
    // }, scope.params.items[1].scope.params.items[0..3]);
}
