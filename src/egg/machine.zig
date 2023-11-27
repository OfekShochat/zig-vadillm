const std = @import("std");
const egg = @import("../egg.zig");
const lisp = @import("../lisp.zig");

pub fn Program(comptime L: type) type {
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

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.insts);
        }

        pub fn get(self: *@This(), index: usize) ?Instruction {
            if (index >= self.insts.len) return null;
            return self.insts[index];
        }

        pub fn compileFrom(allocator: std.mem.Allocator, pattern: PatternAst) !@This() {
            var r2p = std.AutoArrayHashMap(usize, PatternAst).init(allocator);
            var v2r = std.AutoArrayHashMap(usize, usize).init(allocator);
            defer r2p.deinit();
            defer v2r.deinit();

            try r2p.put(0, pattern);

            var insts = std.ArrayList(Instruction).init(allocator);

            var next_reg = 1;
            while (r2p.popOrNull()) |entry| {
                switch (entry.value) {
                    .enode => |enode| {
                        if (enode.children.items.len == 0) {
                            try insts.append(.{ .check = .{ .reg = entry.key, .op = enode } });
                        } else {
                            var len = enode.children().items.len;
                            try insts.append(.{ .bind = .{ .reg = entry.key, .op = enode, .size = len } });

                            for (enode.children(), 0..) |child, i| {
                                try r2p.put(next_reg + i, child);
                            }

                            next_reg += len;
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

            return @This(){ .insts = insts.toOwnedSlice() };
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

                return null;
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
