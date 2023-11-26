const std = @import("std");
const egg = @import("../egg.zig");
const lisp = @import("../lisp.zig");

fn Machine_Instruction(comptime L: type) type {
    return union(enum) {
        Bind: struct { reg: usize, enode: L, size: usize, reg2: usize },
        Check: struct { reg: usize, enode: L },
        Compare: struct { reg1: usize, reg2: usize },
        Yield: std.ArrayList(usize),
    };
}

fn Binder(out: usize, next: usize, searcher: EClassSearcher) type {
    return struct { out = out, next = next, searcher = searcher };
}

fn EClassSearcher(comptime L: type, op: L, len: usize, nodes: []L) type {
    return struct {
        op = op,
        len = len,
        nodes = nodes,
    };
}

fn PatternAst(comptime L: type) type {
    return union {
        ENode: L,
        Var: usize,
    };
}

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

        insts: []const Instruction,

        pub fn get(self: *@This(), index: usize) ?Instruction {
            if (index >= self.insts.len) return null;
            return self.insts[index];
        }

        pub fn compile(
            r2p: std.ArrayHashMap(usize, PatternAst(L)),
            v2r: std.ArrayHash(usize, usize),
            next_reg: usize,
            buf: std.ArrayList(Instruction),
        ) void {
            _ = next_reg;
            var hashmap_iter = r2p.valueIterator();
            while (true) {
                var iter = hashmap_iter.next().?;
                var reg = iter.key();
                var pat = iter.value();
                _ = pat;

                switch (reg) {
                    .PatternAst.ENode => |e| {
                        if (e.children.is_empty()) {
                            try buf.append(.{ .Check = .{ .reg = reg, .enode = e.op } });
                        } else {
                            var len = e.children.len;
                            try buf.append(.{ .Bind = .{ .reg = reg, .enode = e.op, .size = len } });
                            try r2p.appendSlice(e.children);
                        }
                    },

                    .PatternAst.Var => |v| {
                        var v_val = v2r.get(v);
                        if (v_val) |val| {
                            try buf.append(.{ .Compare = .{ .reg1 = val, .reg2 = reg } });
                        } else {
                            try v2r.put(v, reg);
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

pub fn Machine(comptime E: type, comptime L: type) type {
    _ = E;
    return struct {
        program: Program(L),
        regs: std.ArrayList(egg.Id),
        yield_fn: *const fn (egg.Id) void,
        index: usize = 0,
        stack: std.ArrayList(Binder),
        pc: usize,

        fn run(self: *@This(), egraph: anytype) !void {
            while (self.program.get(self.index)) |inst| {
                switch (inst) {
                    .bind => |bind| {
                        const eclass = egraph.get(self.regs.items[bind.reg]).?;
                        var binder = Binder(L){
                            .out = bind.out,
                            .next = self.pc,
                            .searcher = EClassSearcher{
                                .op = bind.op,
                                .len = bind.len,
                                .nodes = eclass.nodes,
                            },
                        };
                        self.stack.append(binder);

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
