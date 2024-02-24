// 1. Take general lowering rewrites from target struct(create it)
// 2. Rewrite everything and extract the relevant rewrite
// 3. Create a cfg
// 4. Create emmiter

const std = @import("std");
const egg = @import("../egg/egg.zig");
const Id = u32;
const rvsdg = @import("ir/rvsdg.zig");

// temporary recExpr object that is the same as the regular one,
// we currently need it because extraction is not merged yet.
pub fn RecExpr(comptime L: type) type {
    return struct {
        expr: std.ArrayList(L),
    };
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

const CFG = struct {
    block_pool: std.ArrayList(BasicBlock),
    graph: std.HashMap(Id, Edge),
    entry_point: Id,
};

pub fn cfgBuilder(comptime L: type, graph: egg.Egraph) type {
    return struct {
        cfg: CFG,
        egraph: graph,

        fn addEdge(from: Id, to: Id) void {
            _ = from;
            _ = to;
        }

        pub fn parseGammaNode(self: *@This(), start_node: rvsdg.GamaNode) void {
            // insert entry block

            var exit_block = BasicBlock();
            exit_block.append(rvsdg.OptBarrier);
            var unified_instruction: L = null;
            var curr_block = BasicBlock(L);

            for (start_node.paths) |path| {
                for (path) |node| {
                    switch (node) {
                        rvsdg.simple => {
                            // non-terminating instruction, add to block
                            curr_block.addInstruction(node);
                        },

                        rvsdg.gamaExit => {
                            // end of if statement
                            self.cfg.block_pool.append(curr_block);
                            self.addEdge(curr_block, exit_block);
                            unified_instruction = self.egraph.get(node.unified_flow_node); //TODO: we wont get an egraph at this points, but a RecExpr, therefore we need to create a function that searches for specific ID inside the recexpr.
                            break;
                        },

                        rvsdg.gama => {
                            self.cfg.block_poo.append(curr_block);
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
