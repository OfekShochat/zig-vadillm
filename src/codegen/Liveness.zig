//! This computes the live ranges of non-static (everything that isn't a constant) values.

const std = @import("std");

const ir = @import("../ir.zig");
const regalloc = @import("regalloc.zig");
const codegen = @import("codegen.zig");

const MachineInst = @import("MachineInst.zig");
const MachineFunction = @import("MachineFunction.zig");
const DominatorTree = @import("../DominatorTree.zig");
const ControlFlowGraph = @import("../ControlFlowGraph.zig");
const LoopAnalysis = @import("../LoopAnalysis.zig");

const Liveness = @This();

// map from a block to all the live-in values in the block
liveins: std.AutoHashMap(ir.Index, std.DynamicBitSetUnmanaged),

// map from a block to all the live-out values in the block
liveouts: std.AutoHashMap(ir.Index, std.DynamicBitSetUnmanaged),

pub fn compute(
    self: *Liveness,
    allocator: std.mem.Allocator,
    domtree: *const DominatorTree,
    cfg: *const ControlFlowGraph,
    func: *const MachineFunction,
) !void {
    try self.computeLiveSets(allocator, cfg, func);
    try self.computeLiveRanges(allocator, cfg, domtree, func);
}

fn upAndMark(
    self: *Liveness,
    allocator: std.mem.Allocator,
    func: *const MachineFunction,
    cfg: *const ControlFlowGraph,
    block_ref: ir.Index,
    v: ir.Index,
) void {
    var operands = std.ArrayList(regalloc.Operand).init(allocator);
    defer operands.deinit();

    const block = func.getBlock(block_ref).?;

    // 2: if def(v) ∈ B (φ excluded) then return # Killed in the block, stop
    for (block.insts) |inst| {
        try inst.getAllocatableOperands(operands);
        for (operands.items) |operand| {
            if (operand.accessType() == .def and operand.vregIndex() == v) return;
        }
        operands.clearRetainingCapacity();
    }

    // 3: if v ∈ LiveIn(B) then return # propagation already done, stop
    var liveins = self.liveins.getPtr(block_ref).?;
    if (liveins.isSet(v)) {
        return;
    }

    // 4: LiveIn(B) = LiveIn(B) ∪ {v}
    liveins.set(v);

    // 5: if v ∈ PhiDefs(B) then return # Do not propagate φ definitions
    for (block.params) |param| {
        if (param.index == v) {
            return;
        }
    }

    // 6: for each P ∈ CFG_preds(B) do # Propagate backward
    for (cfg.preds(block_ref)) |pred_ref| {
        // 7: LiveOut(P) = LiveOut(P ) ∪ {v}
        // 8: Up_and_Mark(B, v)
        self.liveouts.getPtr(pred_ref).?.set(v);
        self.upAndMark(func, cfg, block_ref, v);
    }
}

fn computeLiveSets(
    self: *Liveness,
    allocator: std.mem.Allocator,
    cfg: *const ControlFlowGraph,
    func: *const MachineFunction,
) !void {
    // for all blocks, add their liveins and liveouts, with <number of vregs used> bits.

    // 2: for each basic block B in CFG do # Consider all blocks successively
    for (cfg.rpo) |block_ref| {
        const block = func.getBlock(block_ref).?;

        // 3: for each v ∈ PhiUses(B) do # Used in the φ of a successor block
        for (block.succ_phis) |block_call| {
            // 3: for each v ∈ PhiUses(B) do # Used in the φ of a successor block
            for (block_call.operands) |operand| {
                // 4: LiveOut(B) = LiveOut(B) ∪ {v}
                // 5: Up_and_Mark(B, v)
                self.liveouts.getPtr(block_ref).?.set(operand);
                self.upAndMark(func, block_ref, operand);
            }
        }

        var operands = std.ArrayList(regalloc.Operand).init(allocator);
        defer operands.deinit();

        for (block.insts) |inst| {
            try inst.getAllocatableOperands(operands);

            // 6: for each v used in B (φ excluded) do # Traverse B to find all uses
            for (operands.items) |operand| {
                if (operand.accessType() == .use) {
                    // 7: Up_and_Mark(B, v)
                    self.upAndMark(func, block_ref, operand.vregIndex());
                }
            }
            operands.clearRetainingCapacity();
        }
    }
}

fn computeLiveRanges(
    self: *Liveness,
    allocator: std.mem.Allocator,
    cfg: *const ControlFlowGraph,
    domtree: *const DominatorTree,
    loop_analysis: *const LoopAnalysis,
    func: *const MachineFunction,
) !void {
    _ = cfg;
    _ = domtree;
    _ = loop_analysis;

    var iter = func.blockIter();

    var operands_temp = std.ArrayList(regalloc.Operand).init(allocator);

    while (iter.next()) |block| {
        const liveout = self.liveouts.get(block.id).?.clone(allocator);
        var vreg_iters = liveout.iterator(.{});
        while (vreg_iters.next()) |vreg_index| {
            _ = vreg_index;
            // add a range from the definition (if any, otherwise the start) to the end of the block
        }

        const liveins = self.liveins.get(block.id).?;

        // Killed in this block.
        const killed = liveins.setIntersection(liveout.toggleAll());

        var mapping = std.AutoArrayHashMap(u32, struct { start: codegen.CodePoint, end: codegen.CodePoint }).init(allocator);



        var current = block.start;

        for (block.insts) |inst| {
            try inst.getAllocatableOperands(&operands_temp);

            for (operands_temp.items) |operand| {
                if (killed.isSet(operand.vregIndex()) and operand.accessType() == .def) {
                    try mapping.putNoClobber(operand.vregIndex(), current);
                }
            }

            operands_temp.clearRetainingCapacity();
            current = current.getNextInst();
        }

        vreg_iters = killed.iterator(.{});
        while (vreg_iters.next()) |vreg_index| {
            _ = vreg_index;
        }
    }
}
