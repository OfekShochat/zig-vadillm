// 1. Take general lowering rewrites from target struct(create it)
// 2. Rewrite everything and extract the relevant rewrite
// 3. Create a cfg
// 4. Create emmiter

const std = @import("std");
const egg = @import("../egg/egg.zig");
const Id = u32;
const rvsdg = @import("ir/rvsdg.zig");
const CFG = @import("../ControlFlowGraph.zig").ControlFlowGraph;
const Block = @import("../function.zig").Block;
const Instruction = @import("../instructions.zig").Instruction;

// temporary recExpr object that is the same as the regular one,
// we currently need it because extraction is not merged yet.
pub fn RecExpr(comptime L: type) type {
    return struct { expr: std.AutoArrayHashMap(egg.Id, L) };
}

pub fn BasicBlock(comptime L: type) type {
    return struct {
        instructions: std.ArrayList(L),
        b_id: Id,

        pub fn getTeminator(self: *@This()) L {
            return self.instructions.items[self.instructions.items.len - 1];
        }

        pub fn addInstruction(self: *@This(), inst: L) void {
            self.instructions.append(inst);
        }
    };
}

const Edge = struct {
    preds: std.ArrayList(Id),
    succs: std.ArrayList(Id),
};

// const CFG = struct {
//    block_pool: std.ArrayList(BasicBlock),
//    graph: std.HashMap(Id, Edge),
//    entry_point: Id,
//};

pub fn CfgBuilder(comptime L: type, graph: egg.Egraph, recexp: RecExpr) type {
    return struct {
        cfg: CFG,
        egraph: graph,
        block_pool: std.ArrayList(Block(L)),
        recExp: RecExpr = recexp,

        fn sliceIteratorByValue(iterator: *std.Iterator, value: L) !void {
            while (true) {
                const next = iterator.next();
                if (next.?.value_ptr.* == value) {
                    return;
                } else if (next == null) {
                    return;
                }
            }
        }

        pub fn parseGammaNode(self: *@This(), start_node: rvsdg.gama) void {
            // insert entry block

            const exit_block = BasicBlock();
            //exit_block.append(rvsdg.OptBarrier);
            var unified_instruction: L = null;
            var curr_block = Block(egg.Id);
            for (start_node.paths) |path| {
                var node: rvsdg.Node = recexp.get(path);
                while (true) {
                    switch (node) {
                        rvsdg.simple => {
                            // non-terminating instruction, add to block
                            curr_block.addInstruction(node);
                            var iterator = self.recExp.iterator();
                            sliceIteratorByValue(iterator, node);
                            node = iterator.next().?.value_ptr.*;
                        },

                        rvsdg.gamaExit => {
                            // end of if statement
                            self.block_pool.append(curr_block);
                            self.cfg.addEdge(curr_block.ptr, exit_block.ptr);
                            unified_instruction = recexp.get(node.unified_flow_node); //TODO: we wont get an egraph at this points, but a RecExpr, therefore we need to create a function that searches for specific ID inside the recexpr.
                            break;
                        },

                        rvsdg.gama => {
                            self.cfg.block_pool.append(curr_block);
                            self.parseGammaNode(node);
                        },

                        rvsdg.theta => {},

                        rvsdg.lambda => {},

                        rvsdg.delta => {},

                        rvsdg.omega => {},

                        else => {
                            //block is corrupted?
                        },
                    }
                }
            }

            // insert exit block
            curr_block = BasicBlock(L);
            curr_block.append(unified_instruction);
            self.addEdge(exit_block, curr_block);
        }

        pub fn parseThetaNode() void {}

        pub fn parseLambdaNode() void {}

        pub fn parseDeltaNode() void {}

        pub fn parseOmegaNode() void {}
    };
}

test "test gammanode parsing" {
    comptime var recexp = RecExpr(rvsdg.Node){ .expr = std.AutoArrayHashMap(egg.Id, rvsdg.Node).init(std.testing.allocator) };
    try recexp.expr.putNoClobber(1, rvsdg.GamaNode{ .cond = 2, .paths = []u32{ 3, 5 }, .node_id = 1 });
    // 1.create rec expression
    // 2. call function
    // 3. profit
}
