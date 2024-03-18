// 1. Take general lowering rewrites from target struct(create it)
// 2. Rewrite everything and extract the relevant rewrite
// 3. Create a cfg
// 4. Create emmiter

const std = @import("std");
const egg = @import("../egg/egg.zig");
const Id = u32;
const rvsdg = @import("ir/rvsdg.zig");
const Block = @import("../function.zig").Block;
const Instruction = @import("../instructions.zig").Instruction;
const BinOp = @import("../instructions.zig").BinOp;
const types = @import("../types.zig");

// temporary recExpr object that is the same as the regular one,
// we currently need it because extraction is not merged yet.
pub fn RecExpr(comptime L: type) type {
    return struct { expr: std.AutoArrayHashMap(egg.Id, L) };
}

pub fn BasicBlock(comptime L: type) type {
    return struct {
        instructions: std.ArrayList(L),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .instructions = std.ArrayList(L).init(allocator),
            };
        }

        pub fn getTeminator(self: *@This()) L {
            return self.instructions.items[self.instructions.items.len - 1];
        }

        pub fn addInstruction(self: *@This(), inst: L) !void {
            try self.instructions.append(inst);
        }
    };
}

const Node = struct {
    pred: []u32,
    succ: []u32,
};

// const CFG = struct {
//    block_pool: std.ArrayList(BasicBlock),
//    graph: std.HashMap(Id, Edge),
//    entry_point: Id,
//};

pub fn CFG(comptime L: type) type {
    return struct {
        block_pool: std.AutoHashMap(u32, BasicBlock(L)),
        tree: std.AutoHashMap(u32, Node),
        next_id: u32,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .block_pool = std.AutoHashMap(u32, BasicBlock(L)).init(allocator),
                .tree = std.AutoHashMap(u32, Node).init(allocator),
                .next_id = 0,
            };
        }

        pub fn addNode(self: @This(), node: Node, block: BasicBlock(L)) !void {
            try self.block_pool.putNoClobber(self.next_id, block);
            try self.tree.putNoClobber(self.next_id, node);
            self.next_id = self.next_id + 1;
        }

        pub fn addBlock(self: *@This(), block: BasicBlock(L)) !void {
            try self.block_pool.putNoClobber(self.next_id, block);
            self.next_id = self.next_id + 1;
        }
    };
}

pub fn CfgBuilder(comptime L: type) type {
    return struct {
        cfg: CFG(L),
        block_pool: std.ArrayList(Block),
        recExp: RecExpr(L),
        allocator: std.mem.Allocator,

        pub fn init(recexp: RecExpr(L), allocator: std.mem.Allocator) @This() {
            return @This(){ .recExp = recexp, .cfg = CFG(L).init(allocator), .block_pool = std.ArrayList(Block).init(allocator), .allocator = allocator };
        }

        fn sliceIteratorByKey(iterator: *std.AutoArrayHashMap(u32, L).Iterator, key: u32) void {
            while (true) {
                const next = iterator.next().?;

                if (next.key_ptr.* == key) {
                    return;
                }
            }
        }

        pub fn parseGammaNode(self: *@This(), start_node: rvsdg.GamaNode) !void {
            // insert entry block

            const exit_block = BasicBlock(L);
            //exit_block.append(rvsdg.OptBarrier);
            var unified_instruction: L = self.recExp.expr.get(start_node.paths[0]).?;
            var curr_block = BasicBlock(L).init(self.allocator);
            for (start_node.paths) |path| {
                var node: rvsdg.Node = self.recExp.expr.get(path).?;
                while (true) {
                    switch (node) {
                        rvsdg.Node.simple => {
                            // non-terminating instruction, add to block
                            //curr_block.addInstruction(
                            //    node,
                            //    0,
                            //);
                            try curr_block.addInstruction(node);
                            var iterator = self.recExp.expr.iterator();
                            sliceIteratorByKey(&iterator, path);
                            node = iterator.next().?.value_ptr.*;
                        },

                        rvsdg.Node.gamaExit => {
                            // end of if statement
                            try self.cfg.addBlock(curr_block);
                            try self.cfg.addEdge(curr_block.ptr, exit_block.ptr);
                            const cfg_node = Node{ .pred = []u32{curr_block.ptr}, .succ = []u32{exit_block.ptr} };
                            self.cfg.addNode(cfg_node);
                            unified_instruction = self.recExp.get(node.unified_flow_node); //TODO: we wont get an egraph at this points, but a RecExpr, therefore we need to create a function that searches for specific ID inside the recexpr.
                            break;
                        },

                        rvsdg.Node.gama => {
                            self.cfg.block_pool.append(curr_block);
                            self.parseGammaNode(node);
                        },

                        rvsdg.Node.theta => {},

                        rvsdg.Node.lambda => {},

                        rvsdg.Node.delta => {},

                        rvsdg.Node.omega => {},

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
    var recexp = comptime RecExpr(rvsdg.Node){ .expr = std.AutoArrayHashMap(u32, rvsdg.Node).init(std.testing.allocator) };
    //var egraph = egg.EGraph(rvsdg.Node, rvsdg.Node).init(std.testing.allocator);
    defer recexp.expr.deinit();
    var paths = [2]Id{ 2, 4 };
    const gamanode = rvsdg.Node{ .gama = rvsdg.GamaNode{ .cond = 2, .paths = paths[0..], .node_id = 1 } };
    //var paths_slice = paths.items[0..];
    std.log.info(" {} ", .{gamanode});
    for (gamanode.gama.paths) |i| {
        std.log.info("{}", .{i});
    }

    try recexp.expr.put(1, gamanode);
    try recexp.expr.put(2, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 12, .rhs = 12 } } });
    try recexp.expr.put(4, rvsdg.Node{ .simple = Instruction{ .sub = BinOp{ .lhs = 10, .rhs = 2 } } });
    var builder = CfgBuilder(rvsdg.Node).init(recexp, std.testing.allocator);
    try builder.parseGammaNode(gamanode.gama);
    //builder.parseGammaNode(recexp.expr.get(1));
    // 1.create rec expression
    // 2. call function
    // 3. profit
}
