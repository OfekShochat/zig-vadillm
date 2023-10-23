//! This computes the live ranges of non-static (everything that isn't a constant) values.
//!
//! 1: function Compute_LiveSets_SSA_ByUse(CFG)
//! 2:     for each basic block B in CFG do # Consider all blocks successively
//! 3:         for each v ∈ PhiUses(B) do # Used in the φ of a successor block
//! 4:             LiveOut(B) = LiveOut(B) ∪ {v}
//! 5:             Up_and_Mark(B, v)
//! 6:         for each v used in B (φ excluded) do # Traverse B to find all uses
//! 7:             Up_and_Mark(B, v)
//!
//! 1: function Up_and_Mark(B, v)
//! 2:     if def(v) ∈ B (φ excluded) then return # Killed in the block, stop
//! 3:     if v ∈ LiveIn(B) then return # propagation already done, stop
//! 4:     LiveIn(B) = LiveIn(B) ∪ {v}
//! 5:     if v ∈ PhiDefs(B) then return # Do not propagate φ definitions
//! 6:     for each P ∈ CFG_preds(B) do # Propagate backward
//! 7:         LiveOut(P) = LiveOut(P ) ∪ {v}
//! 8:         Up_and_Mark(P, v)
// phi defs are just the values defined by the block parameters.
// phi uses are whatever we pass as blockcall parameters
// for livein/liveout I think we should use a map to a HashSet (I implemented that in ../hashset.zig)

const std = @import("std");

const ir = @import("../ir.zig");
const regalloc = @import("regalloc.zig");

const MachineInst = @import("MachineInst.zig");
const MachineFunction = @import("MachineFunction.zig");
const DominatorTree = @import("../DominatorTree.zig");
const ControlFlowGraph = @import("../ControlFlowGraph.zig");

const Deque = @import("../deque.zig").Deque;
const HashSet = @import("../hashset.zig").HashSet;

const Liveness = @This();

// map from a block to all the live-in values in the block
liveins: std.AutoHashMap(ir.Index, std.DynamicBitSet),

// map from a block to all the live-out values in the block
liveouts: std.AutoHashMap(ir.Index, std.DynamicBitSet),

const SeparateUses = struct {
    // uses in block-calls
    phi_uses: []const ir.Index,
    // uses not in block-calls
    regular_uses: []const ir.Index,
};

fn computeLiveness(self: *Liveness, allocator: std.mem.Allocator, cfg: *const ControlFlowGraph, func: *const MachineFunction) !void {
    // TODO: add to func vreg_count

    var worklist = std.ArrayList(ir.Index).init(allocator);

    for (func.blocks.items) |block| {
        var livein = self.liveins.getPtr(block);
        livein.* = std.DynamicBitSet.initEmpty(allocator, func.vreg_count);


    }
}
