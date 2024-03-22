const std = @import("std");
const regalloc = @import("regalloc.zig");

const RegisterAllocator = @import("BacktrackingAllocator.zig");

const ControlFlowGraph = @import("../ControlFlowGraph.zig");
const MachineFunction = @import("MachineFunction.zig");
const Object = @import("Object.zig");
const Target = @import("Target.zig");
const Abi = @import("Abi.zig");

pub fn compile(
    allocator: std.mem.Allocator,
    func: *const MachineFunction,
    cfg: *const ControlFlowGraph,
    object: *Object,
    target: Target,
    abi: Abi,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const regalloc_solution = try regalloc.runRegalloc(RegisterAllocator, arena, cfg, abi, func);

    try target.emit(arena.allocator(), func, regalloc_solution, abi, object);
}
