//! This computes the live ranges of non-static (everything that isn't a constant) values.

const std = @import("std");

const MachineInst = @import("MachineInst.zig");

// oh no, I think we have to make another domtree, but now general
const DominatorTree = @import("../DominatorTree.zig");
const ControlFlowGraph = @import("../ControlFlowGraph.zig");

const LiveRanges = @This();

pub fn compute(self: *LiveRanges) !void {
    _ = self;
}
