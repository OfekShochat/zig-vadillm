const std = @import("std");
const egg = @import("../egg.zig");
const lisp = @import("../lisp.zig");

fn Program(comptime L: type) type {
    return struct {
        const Instruction = union(enum) {
            bind: struct {
                reg: usize,
                op: L,
                len: usize,
                out_reg: usize,
            },
            check: struct {
                reg: usize,
                op: L,
            },
            compare: struct { a: usize, b: usize },
            yield: []const usize,
        };

        const PatternAst = union(enum) {
            enode: L,
            symbol: usize,
        };

        insts: []const Instruction,

        pub fn get(self: *@This(), index: usize) ?Instruction {
            if (index >= self.insts.len) return null;
            return self.insts[index];
        }

        pub fn compile(
            r2p: std.AutoHashMap(usize, PatternAst),
            v2r: std.AutoHashMap(usize, usize),
            buf: std.ArrayList(Instruction),
            next_reg: usize,
        ) @This() {
            _ = next_reg;
            var hashmap_iter = r2p.valueIterator();
            while (true) {
                var iter = hashmap_iter.next().?;
                var pattern_reg = iter.key;
                var pattern = iter.value();

                switch (pattern) {
                    .enode => |enode| {
                        if (enode.children.items.len == 0) {
                            try buf.append(.{ .check = .{ .reg = pattern_reg, .enode = enode.op } });
                        } else {
                            var len = enode.children.len;
                            try buf.append(.{ .bind = .{ .reg = pattern_reg, .enode = enode.op, .size = len } });
                            try r2p.appendSlice(enode.children);
                        }
                    },
                    .symbol => |symbol| {
                        if (v2r.get(symbol)) |reg| {
                            try buf.append(.{ .compare = .{ .reg1 = reg, .reg2 = reg } });
                        } else {
                            try v2r.put(symbol, pattern_reg);
                        }
                    },
                }
            }
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
        yield_fn: *const fn (egg.Id) void,
        stack: std.ArrayList(Binder),
        index: usize = 0,

        const EClassSearcher = struct {
            op: L,
            len: usize,
            nodes: []L,

            fn next(self: *EClassSearcher) ?[]egg.Id {
                for (self.nodes, 0..) |node, i| {
                    if (node == self.op and node.children().len == self.len) {
                        self.nodes = self.nodes[i + i ..];
                        return node.children();
                    }
                }
            }
        };
        const Binder = struct { out: usize, next: usize, searcher: EClassSearcher };

        fn backtrack(self: *@This()) !void {
            var binder = self.stack.getLast();
            while (true) {
                if (binder.searcher.next()) |matched| {
                    const new_len = binder.out + matched.items.len;
                    try self.regs.resize(new_len);
                    @memcpy(&self.regs.items[binder.out..new_len], matched.items);

                    self.index = binder.next;
                    break;
                } else {
                    binder = self.stack.pop();
                }
            }
        }

        fn run(self: *@This(), egraph: anytype) !void {
            while (self.program.get(self.index)) |inst| {
                switch (inst) {
                    .bind => |bind| {
                        const eclass = egraph.get(self.regs.items[bind.reg]).?;
                        var binder = Binder{
                            .out = bind.out,
                            .next = self.pc,
                            .searcher = EClassSearcher{
                                .op = bind.op,
                                .len = bind.len,
                                .nodes = eclass.nodes.items,
                            },
                        };

                        try self.stack.append(binder);
                        try self.backtrack();
                    },
                    .check => |check| {
                        const eclass = egraph.get(self.regs.items[check.reg]).?;

                        for (eclass.nodes.items) |node| {
                            if (node.op == check.op and node.children.items.len == 0) {
                                break;
                            }
                        } else {
                            try self.backtrack();
                        }
                    },
                    .compare => |compare| {
                        const enode_a = egraph.find(self.regs.items[compare.a]);
                        const enode_b = egraph.find(self.regs.items[compare.b]);
                        if (enode_a != enode_b) {
                            try self.backtrack();
                        }
                    },
                    .yield => |regs| {
                        self.backtrack() catch {}; // ignore result because we did our part

                        for (regs) |reg| {
                            self.yield_fn(self.regs.items[reg]);
                        }
                    },
                }
            }
        }
    };
}
