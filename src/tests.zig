comptime {
    // utilities
    _ = @import("lisp.zig");

    // datastructures
    _ = @import("types.zig");
    _ = @import("deque.zig");
    _ = @import("list_pool.zig");
    _ = @import("indexed_map.zig");
    _ = @import("hashset.zig");

    // analyses
    _ = @import("DominatorTree.zig");
    _ = @import("LoopAnalysis.zig");
    _ = @import("ControlFlowGraph.zig");

    // submodules
    _ = @import("ir.zig");
    _ = @import("egg.zig");
    _ = @import("egg/egraph.zig");
    _ = @import("codegen.zig");
}
