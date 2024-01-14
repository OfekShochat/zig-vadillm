const egg = @import("../egg/egg.zig");
const std = @import("std");
const Egraph = @import("egraph.zig").EGraph;

pub fn Program(comptime LN: type) type {
    return struct {
        const LT = @typeInfo(LN).Union.tag_type.?;

        insts: []const Instruction,
        r2v: std.AutoArrayHashMap(usize, usize),

        pub const patternAst = union(enum) {
            Enode: struct { op: LT, children: []const patternAst },
            Symbol: usize,
        };

        pub fn deinit(self: *@This()) void {
            self.r2v.deinit();
            std.testing.allocator.free(self.insts);
        }

        pub const Instruction = union(enum) { Bind: struct { reg: usize, op: LT, child_len: usize, out_reg: usize }, Check: struct { reg: usize, op: LT }, Compare: struct { reg1: usize, reg2: usize }, Yield: []const usize };

        pub fn compile(pattern: patternAst) !@This() {
            var r2p = std.AutoArrayHashMap(usize, patternAst).init(std.testing.allocator);
            var v2r = std.AutoArrayHashMap(usize, usize).init(std.testing.allocator);
            var r2v = std.AutoArrayHashMap(usize, usize).init(std.testing.allocator);
            var insts = std.ArrayList(Instruction).init(std.testing.allocator);
            defer r2p.deinit();
            defer insts.deinit();
            defer v2r.deinit();

            var next_reg: usize = 1;
            try r2p.put(0, pattern);
            while (r2p.popOrNull()) |entry| {
                switch (entry.value) {
                    .Enode => |enode| {
                        if (enode.children.len != 0) {
                            try insts.append(Instruction{ .Bind = .{
                                .reg = entry.key,
                                .op = enode.op,
                                .child_len = enode.children.len,
                                .out_reg = next_reg,
                            } });

                            for (enode.children, 0..) |child, i| {
                                std.log.warn("log enode {}", .{next_reg + i});
                                try r2p.put(next_reg + i, child);
                            }

                            next_reg += enode.children.len;

                            std.log.warn("\nbind, next_reg {}\n", .{next_reg});
                        } else {
                            try insts.append(Instruction{ .Check = .{
                                .reg = entry.key,
                                .op = enode.op,
                            } });

                            std.log.warn("\ncheck\n", .{});
                        }
                    },

                    .Symbol => |symbol| {
                        if (v2r.get(symbol)) |r| {
                            std.log.warn("\ncompare {}\n", .{r});
                            try insts.append(Instruction{ .Compare = .{
                                .reg1 = r,
                                .reg2 = entry.key,
                            } });

                            std.log.warn("\ncompare\n", .{});
                        }

                        try v2r.put(symbol, entry.key);
                    },
                }
            }

            try insts.append(Instruction{ .Yield = try std.testing.allocator.dupe(usize, v2r.values()) });

            for (insts.items) |inst| {
                std.log.warn("instruction: {}", .{inst});
            }

            var v2r_iter = v2r.iterator();
            while (v2r_iter.next()) |entry| {
                try r2v.put(entry.value_ptr.*, entry.key_ptr.*);
            }

            return @This(){
                .insts = try insts.toOwnedSlice(),
                .r2v = r2v,
            };
        }

        pub fn get_instruction(self: @This(), index: u32) !Instruction {
            if (self.insts.len < index) {
                return error.Overflow;
            }
            return self.insts[index];
        }
    };
}

pub fn Machine(comptime LN: type) type {
    return struct {
        const LT = @typeInfo(LN).Union.tag_type.?;

        regs: std.ArrayList(egg.Id),
        program: Program(LN),
        b_stack: std.ArrayList(Binder),

        const Binder = struct {
            out_reg: usize,
            next_reg: usize,
            searcher: EClassSearcher,
        }; //A backtraching point for the virtual machine, this will be created for every eclass with children

        const EClassSearcher = struct {
            op: LT,
            len: usize,
            nodes: []LN,

            fn next(self: *EClassSearcher) ?[]const egg.Id {
                //std.log.warn("\nchildren: {}\n", .{self.nodes.len});
                for (self.nodes, 0..) |enode, i| {
                    //std.log.warn("\nchildren: {}\n", .{enode});
                    if (enode == self.op and enode.getChildren().?.len == self.len) {
                        self.nodes = self.nodes[i + 1 ..];
                        std.log.warn("\nchildren: {}, {}\n", .{ enode.getChildren().?[0], enode.getChildren().?[1] });
                        return enode.getChildren();
                    }
                }

                return null;
            }
        };

        pub fn init(_program: Program(LN)) @This() {
            return @This(){
                .program = _program,
                .regs = std.ArrayList(egg.Id).init(std.testing.allocator),
                .b_stack = std.ArrayList(Binder).init(std.testing.allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.program.deinit();
            self.regs.deinit();
            self.b_stack.deinit();
        }

        pub fn backtrack(self: *@This()) !void {
            while (true) {
                // std.log.warn("\nbacktracking\n", .{});
                if (self.b_stack.items.len == 0) {
                    std.log.warn("b_stack empty", .{});
                    return error.StackEmpty;
                }

                var binder = self.b_stack.items[self.b_stack.items.len - 1];
                //var backtrack1 = binder.searcher.next().?;
                //std.log.warn("backtrack regs: {} {}", .{ backtrack1[0], backtrack1[1] });
                if (binder.searcher.next()) |backtrack_entry| {
                    var new_len = backtrack_entry.len + binder.next_reg;
                    try self.regs.resize(new_len);
                    std.log.warn("regs: {} {}", .{ backtrack_entry[0], backtrack_entry[1] });
                    std.log.warn("\nbacktracking: {}\n", .{backtrack_entry.len});
                    @memcpy(self.regs.items[binder.next_reg..new_len], backtrack_entry);
                    break;
                } else {
                    std.log.warn("next didn't worked\n", .{});
                    _ = self.b_stack.popOrNull() orelse return error.StackEmpty;
                }
            }
        }

        pub fn run(self: *@This(), results: *std.AutoArrayHashMap(usize, usize), _eclass: egg.Id, egraph: anytype) !bool {
            try self.regs.append(_eclass);
            var inst_idx: u32 = 0;
            while (true) {
                var inst = try self.program.get_instruction(inst_idx);
                switch (inst) {
                    .Bind => |bind| {
                        try self.b_stack.append(Binder{ .out_reg = bind.reg, .next_reg = bind.out_reg, .searcher = EClassSearcher{
                            .op = bind.op,
                            .len = bind.child_len,
                            .nodes = egraph.get(self.regs.items[bind.reg]).?.nodes.items,
                        } });
                        std.log.warn("\nbinder: {} {} {}\n", .{ self.b_stack.items[0].searcher.nodes.len, self.b_stack.items[0].searcher.op, self.b_stack.items[0].searcher.nodes[0] });
                        self.backtrack() catch return false;
                    },
                    .Check => |check| {
                        var id = self.regs.items[check.reg];
                        var eclass = egraph.get(id).?;
                        for (eclass.nodes.items) |node| {
                            if (node == check.op and node.getChildren().?.len == 0) {
                                break;
                            }
                        } else {
                            try self.backtrack();
                        }
                    },

                    .Compare => |compare| {
                        var a = egraph.find(self.regs.items[compare.reg1]);
                        var b = egraph.find(self.regs.items[compare.reg2]);
                        if (a != b) {
                            try self.backtrack();
                        }
                    },

                    .Yield => |yield| {
                        var matches = std.AutoArrayHashMap(usize, usize).init(std.testing.allocator);
                        defer matches.deinit();
                        std.log.warn("match: {}", .{yield.len});
                        for (yield) |val| {
                            std.log.warn("yield value: {}", .{self.regs.items[val]});
                            try matches.put(self.regs.items[val], val);
                        }

                        results.* = try matches.clone();

                        return true;
                    },
                }

                inst_idx += 1;
            }

            return false;
        }
    };
}
