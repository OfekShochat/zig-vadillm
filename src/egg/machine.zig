const egg = @import("../egg/egg.zig");
const std = @import("std");
const Egraph = @import("egraph.zig").EGraph;

pub fn Program(comptime LN: type) type {
    return struct {
        program_counter: usize = 0,
        var insts = std.ArrayList(Instruction).init(std.testing.allocator);

        pub const patternAst = union(enum) {
            Enode: struct { op: LN, children: []const patternAst },
            Symbol: usize,
        };

        pub const Instruction = union(enum) { Bind: struct { reg: usize, op: LN, child_len: usize, out_reg: usize }, Check: struct { reg: usize, op: LN }, Compare: struct { reg1: usize, reg2: usize }, Yield: usize };

        pub fn compile(pattern: patternAst) !void {
            var r2p = std.AutoArrayHashMap(usize, patternAst).init(std.testing.allocator);
            var v2r = std.AutoArrayHashMap(usize, usize).init(std.testing.allocator);
            defer r2p.deinit();

            var next_reg: usize = 1;
            try r2p.put(0, pattern);
            while (r2p.popOrNull()) |entry| {
                switch (entry.value) {
                    .Enode => |enode| {
                        if (enode.children.len != 0) {
                            try insts.append(Instruction{ .Bind = .{
                                .reg = entry.key,
                                .op = enode.op,
                                .child_len = enode.op.getChildren().?.len,
                                .out_reg = 1,
                            } });

                            for (enode.children, 0..) |child, i| {
                                try r2p.put(next_reg + i, child);
                            }
                        } else {
                            try insts.append(Instruction{ .Check = .{
                                .reg = entry.key,
                                .op = enode.op,
                            } });
                        }
                    },

                    .Symbol => |symbol| {
                        if (v2r.get(symbol)) |r| {
                            try insts.append(Instruction{ .Compare = .{
                                .reg1 = r,
                                .reg2 = entry.key,
                            } });
                        }

                        try v2r.put(symbol, next_reg);
                    },
                }

                next_reg += 1;
            }

            try insts.append(Instruction{
                .Yield = 1,
            });
        }
        pub fn get_next_instruction(self: @This()) !Instruction {
            self.program_counter += 1;
            return insts.items[self.program_counter];
        }
    };
}

pub fn Machine(comptime LN: type) !void {
    return struct {
        regs: std.ArrayList(egg.Id),
        program: Program(LN),
        b_stack: std.ArrayList(Binder),

        const Binder = struct {
            out_reg: usize,
            next_reg: usize,
            searcher: EClassSearcher,
        }; //A backtraching point for the virtual machine, this will be created for every eclass with children

        const EClassSearcher = struct {
            op: LN,
            len: usize,
            nodes: ?[]LN,

            pub fn next(self: *@This()) !?[]LN {
                for (self.nodes, 0..) |enode, i| {
                    if (enode == self.op and enode.children().len.? == self.len) {
                        self.nodes = self.nodes[i + 1 ..];
                        return enode.children().len();
                    }
                }
            }
        };

        pub fn init(self: @This(), _program: Program(LN)) !void {
            self.program = _program;
            self.regs.init(std.testing.Allocator);
            self.b_stack.init(std.testing.Allocator);
        }

        fn backtrack(self: @This()) !void {
            while (true) {
                var entry = self.b_stack.popOrNull();
                if (self.b_stack.items.len == 0) {
                    return;
                }

                if (entry) |backtrack_entry| {
                    var new_len = backtrack_entry.out_reg + .b_stack.items[self.b_stack.items.len - 1];
                    self.regs.resize(new_len);
                    @memcpy(self.regs[backtrack_entry.out_reg], backtrack_entry.searcher.next());
                }

                self.b_stack.popOrNull();
            }
        }

        fn run(self: *@This(), _eclass: egg.Id) !bool {
            while (true) {
                var inst = self._program.get_next_instruction();
                switch (inst) {
                    .Bind => |bind| {
                        self.b_stack.append(Binder{ .out_reg = bind.reg, .next_reg = bind.out_reg, .searcher = .EClassSearcher{
                            .op = bind.op,
                            .len = bind.len,
                            .nodes = self._egraph.get(_eclass).nodes,
                        } });

                        backtrack();
                    },
                    .Check => |check| {
                        var id = self.regs[check.reg];
                        var eclass = self.egraph.get(id);
                        for (eclass.nodes) |node| {
                            if (node == check.op and node.get_children() == 0) {
                                break;
                            }
                        } else {
                            backtrack();
                        }
                    },

                    .Compare => |compare| {
                        var a = self.egraph.find(self.regs.items[compare.reg1]);
                        var b = self.egraph.find(self.regs.items[compare.reg2]);
                        if (a != b) {
                            backtrack();
                        }
                    },

                    .Yield => |yield| {
                        _ = yield;
                        return true;
                    },
                }
            }

            return false;
        }
    };
}
