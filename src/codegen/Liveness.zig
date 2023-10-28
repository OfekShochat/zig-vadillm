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
const ListPool = @import("../list_pool.zig").ListPool;

const Liveness = @This();

// map from a block to all the live-in values in the block
liveins: std.AutoHashMap(ir.Index, std.DynamicBitSetUnmanaged),

// map from a block to all the live-out values in the block
liveouts: std.AutoHashMap(ir.Index, std.DynamicBitSetUnmanaged),

fn computeLiveness(self: *Liveness, allocator: std.mem.Allocator, list_pool: *ListPool(ir.Index), domtree: *const DominatorTree, cfg: *const ControlFlowGraph, func: *const MachineFunction) !void {
    // TODO: add to func vreg_count or commit to a vregs list

    var postorder_iter = cfg.postorderIter();
    while (postorder_iter.next()) |block_ref| {
        var block = func.getBlock(block_ref).?;
        var live = self.liveins.getPtr(block_ref) orelse @panic("rpo has non-existent blocks");

        live.* = std.DynamicBitSetUnmanaged.initEmpty(allocator, func.vreg_count);

        const cfg_node = cfg.get(block_ref) orelse @panic("block indices should be sequential in MachineIR");
        for (cfg_node.preds) |pred_ref| {
            if (!domtree.blockDominates(block_ref, pred_ref)) {
                live.setUnion(self.liveins.get(pred_ref).?);
            }
        }

        for (block.succ_phis) |block_call| {
            // is the first one the block idx or is this not encoded like that? should have a function for that TODO
            for (block_call.args.getSlice(list_pool)) |phi_arg| {
                live.set(phi_arg);
            }
        }

        var bitset_iter = live.iterator();
        while (bitset_iter.next()) |vreg_idx| {
            _ = vreg_idx;
            // TODO: add initial range from block start to block end
        }

        var i: usize = block.insts.len;
        while (i > 0) : (i -= 1) {
            var inst = block.insts[i - 1];
            if (inst.isCall()) {
                // if a register is not defined explicitly for some reason, mark it as clobbered?
            }

            // iterate on all the defs in the inst. add a range from the def to the code position after, and remove the virtual register from live
            // // * For non-call instructions, temps cover both the input and output,
            //   so temps never alias uses (even at-start uses) or defs.
            // * For call instructions, temps only cover the input (the output is
            //   used for the force-spill ranges added above). This means temps
            //   still don't alias uses but they can alias the (fixed) defs. For now
            //   we conservatively require temps to have a fixed register for call
            //   instructions to prevent a footgun.
            // MOZ_ASSERT_IF(ins->isCall(), temp->policy() == LDefinition::FIXED);
            // CodePosition to =
            //     ins->isCall() ? outputOf(*ins) : outputOf(*ins).next();
            //
            // if (!vreg(temp).addInitialRange(alloc(), from, to, &numRanges)) {
            //   return false;
            // }
            // vreg(temp).setInitialDefinition(from);
        }
    }
}
