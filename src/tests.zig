comptime {
    // utilities
    _ = @import("lisp.zig");

    // datastructures
    _ = @import("types.zig");
    _ = @import("deque.zig");
    _ = @import("list_pool.zig");
    _ = @import("indexed_map.zig");
    _ = @import("hashset.zig");
    _ = @import("codegen/interval_tree.zig");

    // analyses
    _ = @import("DominatorTree.zig");
    _ = @import("LoopAnalysis.zig");
    _ = @import("ControlFlowGraph.zig");

    // submodules
    _ = @import("ir.zig");
    _ = @import("egg.zig");
    _ = @import("codegen.zig");

    _ = @import("codegen/BacktrackingAllocator.zig");
    _ = @import("codegen/x64.zig");
}
