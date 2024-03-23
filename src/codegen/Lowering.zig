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
        block_id: u32,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .instructions = std.ArrayList(L).init(allocator),
                .block_id = 0,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.instructions.deinit();
        }

        pub fn getTeminator(self: *@This()) L {
            return self.instructions.items[self.instructions.items.len - 1];
        }

        pub fn addInstruction(self: *@This(), inst: L) !void {
            try self.instructions.append(inst);
        }
    };
}

const Node = struct { pred: []const u32, succ: []const u32 };

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

        pub fn deinit(self: *@This()) void {
            self.tree.deinit();

            var iterator = self.block_pool.valueIterator();
            while (true) {
                if (iterator.next()) |block| {
                    block.deinit();
                } else {
                    break;
                }
            }

            self.block_pool.deinit();
        }

        pub fn addNode(self: *@This(), node: Node, block: BasicBlock(L)) !void {
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
        curr_block_id: u32 = 0,

        pub fn init(recexp: RecExpr(L), allocator: std.mem.Allocator) @This() {
            return @This(){ .recExp = recexp, .cfg = CFG(L).init(allocator), .block_pool = std.ArrayList(Block).init(allocator), .allocator = allocator };
        }

        pub fn deinit(self: *@This()) void {
            self.cfg.deinit();
            self.block_pool.deinit();
        }

        fn sliceIteratorByKey(iterator: *std.AutoArrayHashMap(u32, L).Iterator, key: u32) void {
            while (true) {
                const next = iterator.next().?;
                std.log.warn("next in iterator: key {}, desired key {}", .{ next.key_ptr.*, key });

                if (next.key_ptr.* == key) {
                    return;
                }
            }
        }

        pub fn parseGammaNode(self: *@This(), start_node: rvsdg.GamaNode) !void {
            // insert entry block
            std.log.warn("hello world", .{});
            const exit_block = BasicBlock(L).init(self.allocator);
            //exit_block.append(rvsdg.OptBarrier);
            var unified_instruction: L = self.recExp.expr.get(start_node.paths[0]).?;
            var curr_block = BasicBlock(L).init(self.allocator);
            var keep_iterating = true;
            for (start_node.paths) |path| {
                var node: rvsdg.Node = self.recExp.expr.get(path).?;
                std.log.warn("path: {}", .{path});
                while (keep_iterating) {
                    switch (node) {
                        rvsdg.Node.simple => {
                            std.log.warn("simple node: {}", .{node.simple});
                            // non-terminating instruction, add to block
                            //curr_block.addInstruction(
                            //    node,
                            //    0,
                            //);
                            //std.log.info("simple node: {}", .{node});
                            try curr_block.addInstruction(node);
                            var iterator = self.recExp.expr.iterator();
                            sliceIteratorByKey(&iterator, path);
                            var next = iterator.next();
                            if (next == null) {
                                keep_iterating = false;
                                break;
                            }

                            node = next.?.value_ptr.*;
                            std.log.warn("next node: {}", .{node});
                            break;
                        },

                        rvsdg.Node.gamaExit => {
                            std.log.info("gamaExit: {}", .{node});
                            keep_iterating = false;
                            // end of if statement
                            //const edge = Node{ .pred = [_]u32{curr_block.ptr}[0..], .succ = [_]u32{exit_block.ptr}[0..] };
                            const edge = Node{ .pred = &([1]u32{
                                curr_block.block_id,
                            }), .succ = &([1]u32{
                                exit_block.block_id,
                            }) };
                            try self.cfg.addNode(edge, curr_block);
                            //const cfg_node = Node{ .pred = [_]u32{curr_block.ptr}, .succ = [_]u32{exit_block.ptr} };
                            //self.cfg.addNode(cfg_node);
                            unified_instruction = self.recExp.expr.get(node.gamaExit.unified_flow_node).?; //TODO: we wont get an egraph at this points, but a RecExpr, therefore we need to create a function that searches for specific ID inside the recexpr.
                            self.curr_block_id += 1;
                            break;
                        },

                        rvsdg.Node.gama => {
                            std.log.warn("gamanode: {}", .{node.gama});
                            try self.cfg.addBlock(curr_block);
                            try self.parseGammaNode(node.gama);
                        },

                        rvsdg.Node.theta => {},

                        rvsdg.Node.lambda => {},

                        rvsdg.Node.delta => {},

                        rvsdg.Node.omega => {},

                        else => {
                            std.log.warn("block is corrupted?", .{});
                            //block is corrupted?
                        },
                    }

                    std.log.warn("next block: {}", .{node});
                }

                std.log.warn("last node: ", .{});
            }

            // insert exit block
            curr_block.deinit();
            curr_block = BasicBlock(L).init(self.allocator);
            try curr_block.addInstruction(unified_instruction);
            try self.cfg.addNode(Node{ .pred = &[1]u32{curr_block.block_id}, .succ = &[1]u32{exit_block.block_id} }, curr_block);
        }

        pub fn parseThetaNode() void {}

        pub fn parseLambdaNode() void {}

        pub fn parseDeltaNode() void {}

        pub fn parseOmegaNode() void {}
    };
}

test "test gammanode parsing" {
    std.log.warn("start test", .{});
    var recexp = comptime RecExpr(rvsdg.Node){ .expr = std.AutoArrayHashMap(u32, rvsdg.Node).init(std.testing.allocator) };
    //var egraph = egg.EGraph(rvsdg.Node, rvsdg.Node).init(std.testing.allocator);
    defer recexp.expr.deinit();
    var paths = [2]Id{ 2, 5 };
    var gamanode = rvsdg.Node{ .gama = rvsdg.GamaNode{ .cond = 2, .paths = paths[0..], .node_id = 1 } };
    var gamaexit = rvsdg.Node{ .gamaExit = rvsdg.GamaExitNode{ .unified_flow_node = 5 } };
    //var paths_slice = paths.items[0..];
    std.log.info(" {} ", .{gamanode});
    for (gamanode.gama.paths) |i| {
        std.log.info("{}", .{i});
    }

    try recexp.expr.put(1, gamanode);
    try recexp.expr.put(2, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 12, .rhs = 12 } } });
    try recexp.expr.put(3, rvsdg.Node{ .simple = Instruction{ .mul = BinOp{ .lhs = 20, .rhs = 12 } } });
    try recexp.expr.put(4, gamaexit);
    try recexp.expr.put(5, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 10, .rhs = 10 } } });
    try recexp.expr.put(6, rvsdg.Node{ .simple = Instruction{ .sub = BinOp{ .lhs = 10, .rhs = 2 } } });
    var builder = CfgBuilder(rvsdg.Node).init(recexp, std.testing.allocator);
    defer builder.deinit();
    std.log.warn("hello world", .{});
    try builder.parseGammaNode(gamanode.gama);
    //builder.parseGammaNode(recexp.expr.get(1));
    // 1.create rec expression
    // 2. call function
    // 3. profit
}
