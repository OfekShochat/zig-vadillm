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
const HashSet = @import("../hashset.zig").HashSet;
const BlockId = u32;

// temporary recExpr object that is the same as the regular one,
// we currently need it because extraction is not merged yet.
pub fn RecExpr(comptime L: type) type {
    return struct { expr: std.AutoArrayHashMap(egg.Id, L) };
}

pub fn BasicBlock(comptime L: type) type {
    return struct {
        instructions: std.ArrayList(L),
        block_id: u32,

        pub fn init(allocator: std.mem.Allocator, block_id: u32) @This() {
            return @This(){
                .instructions = std.ArrayList(L).init(allocator),
                .block_id = block_id,
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

const Node = struct { pred: HashSet(BlockId) = .{}, succ: HashSet(BlockId) = .{} };

// const CFG = struct {
//    block_pool: std.ArrayList(BasicBlock),
//    graph: std.HashMap(Id, Edge),
//    entry_point: Id,
//};

pub fn CFG(comptime L: type) type {
    return struct {
        block_pool: std.AutoHashMap(BlockId, BasicBlock(L)),
        edge_pool: std.AutoHashMap(BlockId, Node),
        next_id: BlockId,
        allocator: std.mem.Allocator,
        head_block: BlockId,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .allocator = allocator,
                .block_pool = std.AutoHashMap(BlockId, BasicBlock(L)).init(allocator),
                .edge_pool = std.AutoHashMap(BlockId, Node).init(allocator),
                .next_id = 0,
                .head_block = 0,
            };
        }

        pub fn printTree(self: @This()) void {
            if (self.edge_pool.count() == 0 and self.block_pool.count() == 1) {
                var iterator = self.block_pool.iterator();
                var next = iterator.next().?;
                std.debug.print("No edges, only one block: {}\n", .{next.key_ptr.*});
            }
            var tree_iterator = self.edge_pool.iterator();
            while (true) {
                if (tree_iterator.next()) |node| {
                    std.debug.print("node: {}\n", .{node.key_ptr.*});
                    //var iterator = node.value_ptr.pred.iter();
                    if (node.value_ptr.pred.iter().len > 0) {
                        std.debug.print("preds: [{}, {}] len: {}\n", .{ node.value_ptr.pred.iter().ptr[0], node.value_ptr.pred.iter().ptr[1], node.value_ptr.pred.iter().len });
                    }
                    if (node.value_ptr.succ.iter().len > 0) {
                        std.debug.print("succs: [{}, {}] len: {}\n", .{ node.value_ptr.succ.iter().ptr[0], node.value_ptr.succ.iter().ptr[1], node.value_ptr.succ.iter().len });
                    }
                    //std.debug.print("pred: {}", .{node.value_ptr.*.pred[0]});
                    //std.debug.print("succ: {}", .{node.value_ptr.*.succ[0]});
                } else {
                    return;
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            var block_iterator = self.block_pool.valueIterator();
            while (true) {
                var block = block_iterator.next() orelse break;
                //std.debug.print("free block number {}\n", .{block.block_id});
                block.deinit();
            }

            var edge_iterator = self.edge_pool.valueIterator();
            while (true) {
                var edge = edge_iterator.next() orelse break;
                //std.debug.print("free edge\n", .{});
                edge.*.pred.deinit(self.allocator);
                edge.*.succ.deinit(self.allocator);
            }

            self.edge_pool.deinit();
            self.block_pool.deinit();
        }

        pub fn addNode(self: *@This(), node: Node, block: BasicBlock(L)) !void {
            try self.block_pool.putNoClobber(self.next_id, block);
            try self.tree.putNoClobber(self.next_id, node);
            self.next_id = self.next_id + 1;
        }

        pub fn addEdge(self: *@This(), from: BlockId, to: BlockId) !void {
            var from_node = try self.edge_pool.getOrPutValue(from, Node{});
            var to_node = try self.edge_pool.getOrPutValue(to, Node{});
            try from_node.value_ptr.succ.put(self.allocator, to);
            try to_node.value_ptr.pred.put(self.allocator, from);
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
                if (iterator.next()) |next| {
                    if (next.key_ptr.* == key) {
                        return;
                    }
                }
            }
        }

        pub fn parseGammaNode(self: *@This(), start_node: rvsdg.GamaNode) !void {
            var curr_node_idx: u32 = 0;
            try self.cfg.addEdge(self.curr_block_id - 1, self.curr_block_id);
            var curr_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
            var unified_block_idx: ?u32 = null;
            for (start_node.paths) |path| {
                var node: rvsdg.Node = self.recExp.expr.get(path).?;
                curr_node_idx = path;
                std.debug.print("path: {}\n", .{path});
                while (true) {
                    switch (node) {
                        rvsdg.Node.simple => {
                            // non-terminating instruction, add to block
                            try curr_block.addInstruction(node);
                            var iterator = self.recExp.expr.iterator();
                            sliceIteratorByKey(&iterator, curr_node_idx);
                            var next = iterator.next();
                            if (next == null) {
                                try self.cfg.addBlock(curr_block);
                                self.curr_block_id += 1;
                                curr_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
                                break;
                            }

                            node = next.?.value_ptr.*;
                            curr_node_idx += 1;
                        },

                        rvsdg.Node.gamaExit => {
                            //end of if statement
                            self.curr_block_id += 1;
                            try self.cfg.addBlock(curr_block);
                            if (unified_block_idx == null) {
                                var unified_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
                                const unified_instruction = self.recExp.expr.get(node.gamaExit.unified_flow_node).?;
                                try unified_block.addInstruction(unified_instruction);
                                try self.cfg.addBlock(unified_block);
                                unified_block_idx = self.curr_block_id;
                                self.curr_block_id += 1;
                            }
                            //std.debug.print("[+] create edge from {} to {}\n", .{ curr_block.block_id, unified_block_idx.? });
                            try self.cfg.addEdge(curr_block.block_id, unified_block_idx.?);
                            curr_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
                            if (self.recExp.expr.get(self.curr_block_id)) |next_node| {
                                node = next_node;
                            } else {
                                break;
                            }

                            self.curr_block_id += 1;
                            break;
                        },

                        rvsdg.Node.gama => {
                            try self.cfg.addBlock(curr_block);
                            try self.parseGammaNode(node.gama);
                        },

                        rvsdg.Node.theta => {},

                        rvsdg.Node.lambda => {},

                        rvsdg.Node.delta => {},

                        rvsdg.Node.omega => {},

                        rvsdg.Node.thetaExit => {},

                        else => {
                            //block is corrupted?
                        },
                    }
                }
            }

            // insert exit block
            //curr_block = BasicBlock(L).init(self.allocator, 0);
            //try curr_block.addInstruction(unified_instruction);
            //try self.cfg.addNode(Node{ .pred = &[1]u32{curr_block.block_id}, .succ = &[1]u32{exit_block.block_id} }, curr_block);
        }

        pub fn parseThetaNode(self: *@This(), start_node: rvsdg.ThetaNode) !void {
            try self.cfg.addEdge(self.curr_block_id - 1, self.curr_block_id);
            var loop_body_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
            self.curr_block_id += 1;
            var curr_node_id: Id = start_node.loop_body;
            var curr_node = self.recExp.expr.get(curr_node_id).?;
            while (true) {
                switch (curr_node) {
                    rvsdg.Node.simple => {
                        try loop_body_block.addInstruction(curr_node);
                        var iterator = self.recExp.expr.iterator();
                        sliceIteratorByKey(&iterator, curr_node_id);
                        var next = iterator.next();
                        if (next == null) {
                            break;
                        }

                        curr_node = next.?.value_ptr.*;
                        curr_node_id += 1;
                    },

                    rvsdg.Node.thetaExit => {
                        try self.cfg.addBlock(loop_body_block);
                        break;
                    },

                    rvsdg.Node.gama => {},

                    rvsdg.Node.omega => {},

                    rvsdg.Node.delta => {},

                    rvsdg.Node.lambda => {},

                    rvsdg.Node.gamaExit => {},

                    rvsdg.Node.phi => {},

                    rvsdg.Node.theta => {},
                }
            }

            self.curr_block_id += 1;
            var loop_condition_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
            curr_node_id = start_node.tail_cond;
            curr_node = self.recExp.expr.get(curr_node_id).?;

            while (true) {
                switch (curr_node) {
                    rvsdg.Node.simple => {
                        try loop_condition_block.addInstruction(curr_node);
                        var iterator = self.recExp.expr.iterator();
                        sliceIteratorByKey(&iterator, curr_node_id);
                        curr_node_id += 1;
                        const next = iterator.next();
                        if (next == null) {
                            break;
                        }
                        curr_node = next.?.value_ptr.*;
                    },

                    rvsdg.Node.thetaExit => {
                        try self.cfg.addBlock(loop_condition_block);
                        break;
                    },

                    rvsdg.Node.theta => {},

                    rvsdg.Node.lambda => {},

                    rvsdg.Node.delta => {},

                    rvsdg.Node.omega => {},

                    rvsdg.Node.gama => {},

                    rvsdg.Node.gamaExit => {},

                    rvsdg.Node.phi => {},
                }
            }

            self.curr_block_id += 1;
            var exit_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
            const exit_instruction = self.recExp.expr.get(start_node.exit_node).?;
            try exit_block.addInstruction(exit_instruction);
            try self.cfg.addBlock(exit_block);

            try self.cfg.addEdge(loop_body_block.block_id, loop_condition_block.block_id);
            try self.cfg.addEdge(loop_condition_block.block_id, loop_body_block.block_id);
            try self.cfg.addEdge(loop_condition_block.block_id, exit_block.block_id);
            return;
        }

        pub fn parseLambdaNode() void {}

        pub fn parseDeltaNode() void {}

        pub fn parseOmegaNode() void {}

        pub fn parseFunctionIntoCfg(self: *@This(), start_node: rvsdg.LambdaNode) !void {
            var curr_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
            var curr_node_id = start_node.function_body;
            var curr_node = self.recExp.expr.get(curr_node_id).?;
            while (true) {
                switch (curr_node) {
                    rvsdg.Node.simple => {
                        try curr_block.addInstruction(curr_node);
                        var iterator = self.recExp.expr.iterator();
                        sliceIteratorByKey(&iterator, curr_node_id);
                        curr_node_id += 1;
                        const next = iterator.next();
                        if (next == null) {
                            try self.cfg.addBlock(curr_block);
                            break;
                        }

                        curr_node = next.?.value_ptr.*;
                        curr_node_id += 1;
                    },

                    rvsdg.Node.gama => {
                        try self.cfg.addBlock(curr_block);
                        self.curr_block_id += 1;
                        try self.parseGammaNode(curr_node.gama);
                        var iterator = self.recExp.expr.iterator();
                        const next_node = curr_node.gama.unified_flow_node;
                        sliceIteratorByKey(&iterator, next_node);
                        const next = iterator.next();
                        if (next == null) {
                            try self.cfg.addBlock(curr_block);
                            break;
                        }

                        curr_node = next.?.value_ptr.*;
                        self.curr_block_id += 1;
                        curr_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
                        curr_node_id += 1;
                    },

                    rvsdg.Node.theta => {
                        try self.cfg.addBlock(curr_block);
                        self.curr_block_id += 1;
                        try self.parseThetaNode(curr_node.theta);
                        var iterator = self.recExp.expr.iterator();
                        const next_node = curr_node.theta.exit_node;
                        sliceIteratorByKey(&iterator, next_node);
                        const next = iterator.next();
                        if (next == null) {
                            try self.cfg.addBlock(curr_block);
                            break;
                        }

                        curr_node = next.?.value_ptr.*;
                        self.curr_block_id += 1;
                        curr_block = BasicBlock(L).init(self.allocator, self.curr_block_id);
                        curr_node_id += 1;
                    },

                    rvsdg.Node.lambda => {},

                    rvsdg.Node.omega => {},

                    rvsdg.Node.phi => {},

                    rvsdg.Node.delta => {},

                    rvsdg.Node.thetaExit => {},

                    rvsdg.Node.gamaExit => {},
                }
            }
        }
    };
}

test "test gammanode parsing" {
    std.debug.print("start gama test\n", .{});
    //var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var recexp = RecExpr(rvsdg.Node){ .expr = std.AutoArrayHashMap(u32, rvsdg.Node).init(std.testing.allocator) };
    //var egraph = egg.EGraph(rvsdg.Node, rvsdg.Node).init(std.aren
    defer recexp.expr.deinit();
    var paths = [2]Id{ 2, 5 };
    var gamanode = rvsdg.Node{ .gama = rvsdg.GamaNode{ .cond = 2, .paths = paths[0..], .node_id = 1, .unified_flow_node = 8 } };
    var gamaexit = rvsdg.Node{ .gamaExit = rvsdg.GamaExitNode{ .unified_flow_node = 8 } };
    //var paths_slice = paths.items[0..];
    //std.log.info(" {} ", .{gamanode});
    //for (gamanode.gama.paths) |i| {
    //    std.log.info("{}", .{i});
    //}

    try recexp.expr.put(1, gamanode);
    try recexp.expr.put(2, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 12, .rhs = 12 } } });
    try recexp.expr.put(3, rvsdg.Node{ .simple = Instruction{ .mul = BinOp{ .lhs = 20, .rhs = 12 } } });
    try recexp.expr.put(4, gamaexit);
    try recexp.expr.put(5, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 10, .rhs = 10 } } });
    try recexp.expr.put(6, rvsdg.Node{ .simple = Instruction{ .sub = BinOp{ .lhs = 10, .rhs = 2 } } });
    try recexp.expr.put(7, gamaexit);
    try recexp.expr.put(8, rvsdg.Node{ .simple = Instruction{ .shr = BinOp{ .lhs = 15, .rhs = 39 } } });
    var builder = CfgBuilder(rvsdg.Node).init(recexp, std.testing.allocator);
    builder.curr_block_id += 1;
    defer builder.deinit();
    //std.log.warn("hello world", .{});
    try builder.parseGammaNode(gamanode.gama);
    //builder.cfg.printTree();
    //builder.deinit();
    //std.debug.print("------------------------------------------------------------------------------------", .{});
    //builder.cfg.printTree();
    //builder.parseGammaNode(recexp.expr.get(1));
    // 1.create rec expression
    // 2. call function
    // 3. profit
}

test "test thetanode parsing" {
    std.debug.print("start theta test\n", .{});
    var recexp = RecExpr(rvsdg.Node){ .expr = std.AutoArrayHashMap(u32, rvsdg.Node).init(std.testing.allocator) };
    defer recexp.expr.deinit();

    var thetanode = rvsdg.Node{ .theta = rvsdg.ThetaNode{ .node_id = 1, .tail_cond = 2, .loop_body = 5, .exit_node = 8 } };
    try recexp.expr.put(1, thetanode);
    try recexp.expr.put(2, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 10, .rhs = 12 } } });
    try recexp.expr.put(3, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 12, .rhs = 20 } } });
    try recexp.expr.put(4, rvsdg.Node{ .thetaExit = rvsdg.ThetaExitNode{ .node_id = 4 } });
    try recexp.expr.put(5, rvsdg.Node{ .simple = Instruction{ .sub = BinOp{ .lhs = 15, .rhs = 17 } } });
    try recexp.expr.put(6, rvsdg.Node{ .simple = Instruction{ .mul = BinOp{ .lhs = 17, .rhs = 19 } } });
    try recexp.expr.put(7, rvsdg.Node{ .thetaExit = rvsdg.ThetaExitNode{ .node_id = 7 } });
    try recexp.expr.put(8, rvsdg.Node{ .simple = Instruction{ .shr = BinOp{ .rhs = 16, .lhs = 29 } } });
    var builder = CfgBuilder(rvsdg.Node).init(recexp, std.testing.allocator);
    builder.curr_block_id += 1;

    try builder.parseThetaNode(thetanode.theta);
    builder.cfg.printTree();
    builder.deinit();
}

test "test rvsdg function to cfg" {
    std.debug.print("\nstart rvsdg->cfg test:\n", .{});
    var recexp = RecExpr(rvsdg.Node){ .expr = std.AutoArrayHashMap(u32, rvsdg.Node).init(std.testing.allocator) };
    defer recexp.expr.deinit();
    var arguments = [2]u32{ 100, 101 };
    var lambdanode = rvsdg.Node{ .lambda = rvsdg.LambdaNode{ .node_id = 1, .function_body = 2, .arguments = arguments[0..], .output = 100 } };
    try recexp.expr.put(1, lambdanode);
    try recexp.expr.put(2, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 10, .rhs = 12 } } });
    try recexp.expr.put(3, rvsdg.Node{ .simple = Instruction{ .add = BinOp{ .lhs = 12, .rhs = 20 } } });
    //try recexp.expr.put(4, rvsdg.Node{ .thetaExit = rvsdg.ThetaExitNode{ .node_id = 4 } });
    try recexp.expr.put(4, rvsdg.Node{ .simple = Instruction{ .sub = BinOp{ .lhs = 15, .rhs = 17 } } });
    try recexp.expr.put(5, rvsdg.Node{ .simple = Instruction{ .mul = BinOp{ .lhs = 17, .rhs = 19 } } });
    //try recexp.expr.put(7, rvsdg.Node{ .thetaExit = rvsdg.ThetaExitNode{ .node_id = 7 } });
    try recexp.expr.put(6, rvsdg.Node{ .simple = Instruction{ .shr = BinOp{ .rhs = 16, .lhs = 29 } } });

    var builder = CfgBuilder(rvsdg.Node).init(recexp, std.testing.allocator);
    try builder.parseFunctionIntoCfg(lambdanode.lambda);

    builder.cfg.printTree();
    builder.deinit();
}
