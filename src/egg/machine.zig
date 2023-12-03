const std = @import("std");
const egg = @import("../egg.zig");

const Match = egg.Match;
const Substitution = egg.Substitution;

pub fn Program(comptime L: type) type {
    return struct {
        const LT = @typeInfo(L).Union.tag_type.?;

        const Instruction = union(enum) {
            bind: struct {
                reg: usize,
                op: LT,
                len: usize,
                out_reg: usize,
            },
            check: struct {
                reg: usize,
                op: LT,
            },
            compare: struct { a: usize, b: usize },
            yield: []const usize,
        };

        pub const PatternAst = union(enum) {
            enode: struct { op: LT, children: ?[]const PatternAst },
            symbol: usize,
        };

        insts: []const Instruction,
        r2v: std.AutoHashMap(usize, usize),

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.insts[self.insts.len - 1].yield);
            allocator.free(self.insts);
            self.r2v.deinit();
        }

        pub fn get(self: *@This(), index: usize) ?Instruction {
            if (index >= self.insts.len) return null;
            return self.insts[index];
        }

        pub fn compileFrom(allocator: std.mem.Allocator, pattern: PatternAst) !@This() {
            var v2r = std.AutoArrayHashMap(usize, usize).init(allocator);
            var r2p = std.AutoArrayHashMap(usize, PatternAst).init(allocator);
            defer v2r.deinit();
            defer r2p.deinit();

            try r2p.put(0, pattern);
            var next_reg: usize = 1;
            var insts = std.ArrayList(Instruction).init(allocator);

            while (r2p.popOrNull()) |entry| {
                switch (entry.value) {
                    .enode => |enode| {
                        if (enode.children) |children| {
                            try insts.append(.{ .bind = .{
                                .reg = entry.key,
                                .op = enode.op,
                                .len = children.len,
                                .out_reg = next_reg,
                            } });

                            for (children, 0..) |child, i| {
                                try r2p.put(next_reg + i, child);
                            }

                            next_reg += children.len;
                        } else {
                            try insts.append(.{ .check = .{ .reg = entry.key, .op = enode.op } });
                        }
                    },
                    .symbol => |symbol| {
                        if (v2r.get(symbol)) |reg| {
                            try insts.append(.{ .compare = .{ .a = reg, .b = entry.key } });
                        } else {
                            try v2r.put(symbol, entry.key);
                        }
                    },
                }
            }

            try insts.append(.{ .yield = try allocator.dupe(usize, v2r.values()) });

            var r2v = std.AutoHashMap(usize, usize).init(allocator);

            var iter = v2r.iterator();
            while (iter.next()) |entry| {
                try r2v.put(entry.value_ptr.*, entry.key_ptr.*);
            }

            return @This(){
                .insts = try insts.toOwnedSlice(),
                .r2v = r2v,
            };
        }
    };
}

pub fn parseProgram(comptime L: type, comptime source: []const u8) !Program(L) {
    _ = source;
    return error.NotImplemented;
}

pub fn Machine(comptime L: type) type {
    return struct {
        program: Program(L),
        regs: std.ArrayList(egg.Id),
        stack: std.ArrayList(Binder),
        index: usize = 0,

        const LT = @typeInfo(L).Union.tag_type.?;

        const EClassSearcher = struct {
            op: LT,
            len: usize,
            nodes: []L,

            fn next(self: *EClassSearcher) ?[]const egg.Id {
                for (self.nodes, 0..) |node, i| {
                    // TODO(ghostway): possible bug when len == 0
                    if (node == self.op and node.getChildren().?.len == self.len) {
                        self.nodes = self.nodes[i + 1 ..];
                        return node.getChildren();
                    }
                }

                return null;
            }
        };

        const Binder = struct { out: usize, next: usize, searcher: EClassSearcher };

        pub fn init(program: Program(L), allocator: std.mem.Allocator) @This() {
            return @This(){
                .program = program,
                .regs = std.ArrayList(egg.Id).init(allocator),
                .stack = std.ArrayList(Binder).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.regs.deinit();
            self.stack.deinit();
        }

        fn backtrack(self: *@This()) !void {
            while (true) {
                if (self.stack.items.len == 0) {
                    return error.StackEmpty;
                }

                var binder = &self.stack.items[self.stack.items.len - 1];

                if (binder.searcher.next()) |matched| {
                    const new_len = binder.out + matched.len;
                    try self.regs.resize(new_len);
                    @memcpy(self.regs.items[binder.out..new_len], matched);
                    self.index = binder.next;
                    break;
                } else {
                    _ = self.stack.popOrNull() orelse return error.StackEmpty;
                }
            }
        }

        pub fn reset(self: *@This()) void {
            self.regs.clearAndFree();
            self.stack.clearAndFree();
            self.index = 0;
        }

        pub fn resetRetainingCapacity(self: *@This()) void {
            self.regs.clearRetainingCapacity();
            self.stack.clearRetainingCapacity();
            self.index = 0;
        }

        pub fn run(
            self: *@This(),
            egraph: anytype,
            results: *egg.MatchResultsArray,
            root: egg.Id,
            allocator: std.mem.Allocator,
        ) !void {
            self.resetRetainingCapacity();
            try self.regs.append(root);
            try self.runInternal(egraph, allocator, results);
        }

        pub fn runInternal(
            self: *@This(),
            egraph: anytype,
            allocator: std.mem.Allocator,
            results: *egg.MatchResultsArray,
        ) !void {
            var matches = std.ArrayList(Match).init(allocator);
            defer matches.deinit();

            while (self.program.get(self.index)) |inst| {
                self.index += 1;

                switch (inst) {
                    .bind => |bind| {
                        const eclass = egraph.get(self.regs.items[bind.reg]).?;
                        var binder = Binder{
                            .out = bind.out_reg,
                            .next = self.index,
                            .searcher = EClassSearcher{
                                .op = bind.op,
                                .len = bind.len,
                                .nodes = eclass.nodes.items,
                            },
                        };

                        try self.stack.append(binder);

                        self.backtrack() catch return;
                    },
                    .check => |check| {
                        const eclass = egraph.get(self.regs.items[check.reg]).?;

                        for (eclass.nodes.items) |node| {
                            if (node == check.op and node.getChildren() == null) {
                                break;
                            }
                        } else {
                            self.backtrack() catch return;
                        }
                    },
                    .compare => |compare| {
                        const a = egraph.find(self.regs.items[compare.a]);
                        const b = egraph.find(self.regs.items[compare.b]);
                        if (a != b) {
                            self.backtrack() catch return;
                        }
                    },
                    .yield => |regs| {
                        try matches.ensureTotalCapacity(regs.len);

                        for (regs) |reg| {
                            try matches.append(Match{
                                .symbol = self.program.r2v.get(reg) orelse @panic("r2v is invalid: compilation is broken"),
                                .id = self.regs.items[reg],
                            });
                        }

                        try results.append(try matches.toOwnedSlice());
                        self.backtrack() catch return;
                    },
                }
            }
        }
    };
}
