const std = @import("std");
const BlockRef = @import("main.zig").BlockRef;
const DominatorTree = @import("DominatorTree.zig");
const ControlFlowGraph = @import("main.zig").ControlFlowGraph;

const LoopAnalysis = @This();

pub const LoopRef = u32;

pub const Loop = struct {
    header: BlockRef,
    parent: ?LoopRef,
    level: u8,
};

loops: std.AutoArrayHashMapUnmanaged(LoopRef, Loop) = .{},
block_map: std.AutoArrayHashMapUnmanaged(BlockRef, LoopRef) = .{},
loop_ref: LoopRef = 0,

pub fn deinit(self: *LoopAnalysis, allocator: std.mem.Allocator) void {
    self.loops.deinit(allocator);
    self.block_map.deinit(allocator);
}

pub fn compute(
    self: *LoopAnalysis,
    allocator: std.mem.Allocator,
    domtree: *const DominatorTree,
    cfg: *const ControlFlowGraph,
) !void {
    try self.findLoopHeaders(allocator, domtree, cfg);
    try self.discoverLoopBlocks(allocator, domtree, cfg);
}

fn findLoopHeaders(
    self: *LoopAnalysis,
    allocator: std.mem.Allocator,
    domtree: *const DominatorTree,
    cfg: *const ControlFlowGraph,
) !void {
    var iter = domtree.reversePostorderIter();
    while (iter.next()) |block_ref| {
        const preds = cfg.get(block_ref).?.preds;
        for (preds.iter()) |pred| {
            if (domtree.dominates(block_ref, pred)) {
                try self.loops.put(allocator, self.loop_ref, Loop{
                    .header = block_ref,
                    .parent = null,
                    .level = @intCast(0xFF),
                });
                self.loop_ref += 1;
            }
        }
    }
}

fn findOutermostEnclosingLoop(self: *LoopAnalysis, loop_ref: LoopRef) LoopRef {
    var current_loop = loop_ref;

    // warning: infinite loop is possible if there are loops inside the parents (shouldn't happen)
    while (true) {
        const loop = self.loops.getPtr(current_loop).?;

        if (loop.parent) |parent| {
            current_loop = parent;
        } else {
            return current_loop;
        }
    }
}

fn discoverLoopBlocks(
    self: *LoopAnalysis,
    allocator: std.mem.Allocator,
    domtree: *const DominatorTree,
    cfg: *const ControlFlowGraph,
) !void {
    var stack = std.ArrayList(BlockRef).init(allocator);
    defer stack.deinit();

    var iter = self.loops.iterator();
    while (iter.next()) |kv| {
        const curr_loop = kv.key_ptr.*;

        // step 1: find backedges and add to stack
        for (cfg.get(kv.value_ptr.header).?.preds.iter()) |pred| {
            if (domtree.dominates(kv.value_ptr.header, pred)) {
                try stack.append(pred);
            }
        }

        // step 2: DFS on each backedge, go backward to find any not-yet-added subloops.
        while (stack.items.len > 0) {
            const block_ref = stack.pop();

            if (self.block_map.get(block_ref)) |loop_from_block| {
                // step 2.2: if you found a node again, there's another loop somewhere.
                // check if the loop is already registered in the current loop.
                const outermost_loop = self.findOutermostEnclosingLoop(loop_from_block);

                // step 2.3: register the loop into the current one and continue from its header. if
                // the outermost loop is the same as the current one, the loop is known and you can
                // stop dfs there.
                if (outermost_loop != curr_loop) {
                    const subloop = self.loops.getPtr(outermost_loop).?;
                    subloop.parent = curr_loop;

                    for (cfg.get(subloop.header).?.preds.iter()) |pred| {
                        try stack.append(pred);
                    }
                }
            } else {
                // step 2.1: if you find a node you didn't encounter, add it to the current loop.
                try self.block_map.put(allocator, block_ref, curr_loop);
            }
        }
    }
}

const Signature = @import("main.zig").Signature;
const Module = @import("main.zig").Module;
const Function = @import("main.zig").Function;
const ValueRef = @import("main.zig").ValueRef;
const HashSet = @import("main.zig").HashSet;

test "wta" {
    const types = @import("types.zig");
    const Instruction = @import("main.zig").Instruction;
    var allocator = std.testing.allocator;

    var func = Function.init(allocator, "add", Signature{
        .ret = types.I32,
        .args = .{},
    });
    defer func.deinit(allocator);

    try func.appendParam(allocator, types.I32);

    const block1 = try func.appendBlock(allocator);
    const block2 = try func.appendBlock(allocator);
    const block3 = try func.appendBlock(allocator);
    const block4 = try func.appendBlock(allocator);
    const param1 = try func.appendBlockParam(allocator, block1, types.I32);

    const const1 = try func.addConst(allocator, &std.mem.toBytes(10), types.I32);

    var args = std.ArrayListUnmanaged(ValueRef){};
    try args.append(allocator, const1);
    defer args.deinit(allocator);
    _ = try func.appendInst(
        allocator,
        block1,
        Instruction{ .jump = .{ .block = block2, .args = args } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block2,
        Instruction{ .jump = .{ .block = block3, .args = args } },
        types.I32,
    );

    const cond = try func.appendInst(
        allocator,
        block3,
        Instruction{ .icmp = .{ .cond_code = .UnsignedLessThan, .lhs = param1, .rhs = const1 } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block3,
        Instruction{ .brif = .{
            .cond = cond,
            .cond_true = .{ .block = block2, .args = .{} },
            .cond_false = .{ .block = block4, .args = .{} },
        } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block4,
        Instruction{ .ret = null },
        types.I32,
    );

    var cfg = try ControlFlowGraph.fromFunction(allocator, &func);
    defer cfg.deinit(allocator);

    var domtree = DominatorTree{};
    defer domtree.deinit(allocator);

    try domtree.compute(allocator, &cfg, &func);

    var loop_analysis = LoopAnalysis{};
    defer loop_analysis.deinit(allocator);
    try loop_analysis.compute(allocator, &domtree, &cfg);
    std.debug.print("{any}\n", .{loop_analysis.loops.get(0)});
}
