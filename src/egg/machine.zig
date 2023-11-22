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

        insts: []const Instruction,

        pub fn get(self: *@This(), index: usize) ?Instruction {
            if (index >= self.insts.len) return null;
            return self.insts[index];
        }
    };
}

pub fn parseProgram(comptime L: type, comptime source: []const u8) !Program(L) {
    _ = source;
    return error.NotImplemented;
}

pub fn Machine(comptime E: type, comptime L: type) type {
    return struct {
        program: Program(L),
        regs: std.ArrayList(egg.Id),
        yield_fn: *const fn(egg.Id) void,
        index: usize = 0,

        fn run(self: *@This(), egraph: anytype) !void {
            while (self.program.get(self.index)) |inst| {
                switch (inst) {
                    .bind => |bind| {
                        const eclass = egraph.get(self.regs.items[bind.reg]).?;
                        _ = eclass;

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
