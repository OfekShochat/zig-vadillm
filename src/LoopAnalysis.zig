const std = @import("std");
const Index = @import("ir.zig").Index;
const DominatorTree = @import("DominatorTree.zig");
const ControlFlowGraph = @import("ControlFlowGraph.zig");

const LoopAnalysis = @This();

pub const LoopRef = u32;
pub const INVALID_LOOP_LEVEL = 0xFF;

pub const Loop = struct {
    header: Index,
    parent: ?LoopRef,
    level: u8,
};

loops: std.AutoArrayHashMapUnmanaged(LoopRef, Loop) = .{},
block_map: std.AutoArrayHashMapUnmanaged(Index, LoopRef) = .{},
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
    try self.assignLoopLevels(allocator);
}

pub fn clear(self: *LoopAnalysis) !void {
    self.block_map.clearRetainingCapacity();
    self.loops.clearRetainingCapacity();
}

pub fn clearAndFree(self: *LoopAnalysis, allocator: std.mem.Allocator) !void {
    self.block_map.clearAndFree(allocator);
    self.loops.clearAndFree(allocator);
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
                    .level = @intCast(INVALID_LOOP_LEVEL),
                });
                try self.block_map.put(allocator, block_ref, self.loop_ref);
                self.loop_ref += 1;
                break;
            }
        }
    }
}

fn findOutermostEnclosingLoop(self: *LoopAnalysis, loop_ref: LoopRef) LoopRef {
    var current_loop = loop_ref;

    // warning: infinite loop is possible if there are loops inside the parents (shouldn't happen)
    // this is to prevent that in debug mode.
    var i: u32 = 0;

    while (true) {
        std.debug.assert(i < INVALID_LOOP_LEVEL);
        i += 1;

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
    var stack = std.ArrayList(Index).init(allocator);
    defer stack.deinit();

    var iter = self.loops.iterator();
    while (iter.next()) |loop_entry| {
        const curr_loop = loop_entry.key_ptr.*;

        // step 1: find backedges and add to stack.
        for (cfg.get(loop_entry.value_ptr.header).?.preds.iter()) |pred| {
            if (domtree.dominates(loop_entry.value_ptr.header, pred)) {
                try stack.append(pred);
            }
        }

        // step 2: DFS on each backedge, go backward to find any not-yet-added subloops.
        while (stack.items.len > 0) {
            const block_ref = stack.pop();

            if (self.block_map.get(block_ref)) |loop| {
                // step 2.2: if you found a node again (or this is a backedge that we added earlier),
                // there's another loop somewhere. check if that loop is already registered in the
                // current loop.
                const outermost_loop = self.findOutermostEnclosingLoop(loop);

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

fn assignLoopLevels(self: *LoopAnalysis, allocator: std.mem.Allocator) !void {
    var stack = std.ArrayList(LoopRef).init(allocator);
    defer stack.deinit();

    for (self.loops.entries.items(.key)) |loop| {
        if (self.loops.get(loop).?.level == INVALID_LOOP_LEVEL) {
            try stack.append(loop);

            // DFS on the parents until there's no parent or the parent has already been processed
            // starting at each backedge.
            while (stack.getLastOrNull()) |lp| {
                if (self.loops.getPtr(lp).?.parent) |parent_ref| {
                    var parent = self.loops.getPtr(parent_ref) orelse @panic("bad parent ref from `discoverLoopBlocks");

                    if (parent.level != INVALID_LOOP_LEVEL) {
                        // the current loop level is the parent's + 1
                        self.loops.getPtr(lp).?.level = parent.level + 1;
                        _ = stack.pop();
                    } else {
                        // if the parent hasn't been processed yet, retain the current loop for later
                        // and process the parent first.
                        try stack.append(parent_ref);
                    }
                } else {
                    // no parent, just a lone loop. we should get here eventually for the outermost loops.
                    self.loops.getPtr(lp).?.level = 1;
                    _ = stack.pop();
                }
            }
        }
    }
}

const Module = @import("Module.zig");
const Function = @import("function.zig").Function;
const Signature = @import("function.zig").Signature;
const HashSet = @import("hashset.zig").HashSet;

test "loop analysis" {
    const types = @import("types.zig");
    const Instruction = @import("instructions.zig").Instruction;
    var allocator = std.testing.allocator;

    var func = Function.init(allocator, Signature{
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

    var args = std.ArrayListUnmanaged(Index){};
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

    try domtree.compute(allocator, &cfg);

    var loop_analysis = LoopAnalysis{};
    defer loop_analysis.deinit(allocator);

    try loop_analysis.compute(allocator, &domtree, &cfg);
    std.debug.print("{any}\n", .{loop_analysis.loops.get(0)});
}
