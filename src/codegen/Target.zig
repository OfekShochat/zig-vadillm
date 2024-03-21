const std = @import("std");

const MachineFunction = @import("MachineFunction.zig");
const Object = @import("Object.zig");
const Abi = @import("Abi.zig");
const regalloc = @import("regalloc.zig");

const Self = @This();

pub const VTable = struct {
    emitNops: *const fn (*std.io.AnyWriter, n: usize) anyerror!void,

    emitStitch: *const fn (*std.io.AnyWriter, from: regalloc.Allocation, to: regalloc.Allocation) anyerror!void,

    /// Store caller's stack-frame and (clobbered) callee saved regsiters, and setup the new one.
    emitPrologue: *const fn (
        *std.io.AnyWriter,
        allocated_size: usize,
        save: []const regalloc.PhysicalReg,
    ) anyerror!void,

    /// Restore the caller's stack frame and callee-saved registers, then returns.
    emitEpilogue: *const fn (
        *std.io.AnyWriter,
        allocated_size: usize,
        saved: []const regalloc.PhysicalReg,
    ) anyerror!void,
};

vtable: VTable,

/// in bytes
block_alignment: usize = 16,

/// in bytes
word_size: usize = 8,

/// in bytes
stack_alignment: usize = 16,

pub fn emit(
    self: *Self,
    allocator: std.mem.Allocator,
    func: *const MachineFunction,
    regalloc_solution: *regalloc.SolutionConsumer,
    abi: Abi,
    object: *Object,
) !void {
    const allocated_stack_size = func.getMaxAllocatedStackSize();
    var clobbered_callee_saved = std.AutoArrayHashMap(regalloc.PhysicalReg, void).init(allocator);
    defer clobbered_callee_saved.deinit();

    // HACK: `regalloc_solution.ranges` is pretty much a hack.
    try regalloc.getClobberedRegs(func, regalloc_solution.ranges, &clobbered_callee_saved);

    for (abi.call_conv.callee_saved) |preg| {
        _ = clobbered_callee_saved.orderedRemove(preg);
    }

    try self.vtable.emitPrologue(&object.code_buffer, allocated_stack_size, clobbered_callee_saved.keys());

    var iter = func.blockIter();
    while (iter.next()) |block| {
        try self.emitBlock(block, regalloc_solution, &object.code_buffer);
    }

    try self.vtable.emitEpilogue(&object.code_buffer, allocated_stack_size, clobbered_callee_saved.keys());
}

fn emitBlock(
    self: *Self,
    block: MachineFunction.MachBlock,
    regalloc_solution: *regalloc.SolutionConsumer,
    buffer: *std.io.AnyWriter,
) !void {
    // TODO: should I go back to a wrapper structure just for this?
    // const required_padding = (self.block_alignment - self.current_offset % self.block_alignment) % self.block_alignment;
    // try self.vtable.emitNops(buffer, required_padding);

    for (block.insts) |inst| {
        const solution_point = try regalloc_solution.advance();

        try self.emitStitches(buffer, solution_point.stitches);
        try inst.emit(buffer, solution_point.mapping);
    }
}

fn emitStitches(
    self: *Self,
    buffer: *std.io.AnyWriter,
    stitches: []const regalloc.Stitch,
) !void {
    // const stitches = try solveParallelStitches(unordered_stitches);

    for (stitches) |stitch| {
        try self.vtable.emitStitch(buffer, stitch.from, stitch.to);
    }
}
