//! This computes the live ranges of non-static (everything that isn't a constant) values.

const std = @import("std");

const ir = @import("../ir.zig");
const regalloc = @import("regalloc.zig");

const MachineInst = @import("MachineInst.zig");
const MachineFunction = @import("MachineFunction.zig");
const DominatorTree = @import("../DominatorTree.zig");
const ControlFlowGraph = @import("../ControlFlowGraph.zig");

const Deque = @import("../deque.zig").Deque;
const HashSet = @import("../hashset.zig").HashSet;

const LiveRanges = @This();

pub const LiveRange = struct {
    start: ir.Index,
    end: ir.Index,
};

const IndexSet = std.ArrayHashMapUnmanaged(ir.Index, bool);

liveouts: std.ArrayHashMapUnmanaged(ir.Index, std.DynamicBitSetUnmanaged),

pub fn compute(self: *LiveRanges) !void {
    _ = self;
}

fn computeLiveRangesForVirt(
    self: *LiveRanges,
    allocator: std.mem.Allocator,
    func: *MachineFunction,
    cfg: *const ControlFlowGraph,
    domtree: *const DominatorTree,
) !void {
    var visited = HashSet(ir.Index);
    var stack = try Deque(ir.Index).init(allocator);
    try stack.appendSlice(domtree.postorder);

    var operands_temp = std.ArrayList(regalloc.Operand).init(allocator);

    while (stack.popFront()) |block_ref| {
        const insts = func.instructionsFor(block_ref) orelse @panic("invalid blocks in stack (workqueue)");
        var live = self.liveouts.get(block_ref).?.clone();

        // set all block-call arguments as live

        for (insts) |inst| {
            try inst.getAllocatableOperands(&operands_temp);
            for (operands_temp.items) |operand| {
                live.setValue(operand.vregIndex(), operand.accessType() == .use);
            }
        }

        for (func.blockParams(block_ref)) |param| {
            live.unset(param.vregIndex());
        }

        const cfg_node = cfg.get(block_ref) orelse @panic("invalid blocks in stack (workqueue)");
        for (cfg_node.preds) |pred_ref| {
            const changed = self.liveouts.getPtr(pred_ref).?.unionWith(live);
            if (changed and !visited.contains(pred_ref)) {
                try stack.append(pred_ref);
                try visited.put(allocator, pred_ref);
            }
        }

        var live_ins = self.live_ins.getOrPut(block_ref).value_ptr;
        live_ins.* = live;
    }
}
