const std = @import("std");
const LivenessAnalysis = @import("livenesAnalysis.zig").LivenessAnalysis;

pub const InterferenceGraph = struct {
    edges: ArrayList = {};


    pub fn buildGraph(LivenessAnalysis* liveness) {
        //run getIntersections() on every virtual register, when something intersects, then create an edge to it
    }

    pub fn getIntersections(Index virt_reg) {
        liveness.
        //get liverange of virtual register from liveness analysis, then loop through all the liveranges and check if there any one that lives during the same range
    }

}