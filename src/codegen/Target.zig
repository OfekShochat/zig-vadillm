const std = @import("std");

const MachineFunction = @import("MachineFunction.zig");
const Object = @import("Object.zig");
const Abi = @import("Abi.zig");
const regalloc = @import("regalloc.zig");

const Self = @This();

pub const VTable = struct {
    emitNops: *const fn (*std.io.AnyWriter, n: usize) anyerror!void,

    emitStitch: *const fn (*std.io.AnyWriter, from: regalloc.Allocation, to: regalloc.Allocation) anyerror!void,

    /// Store the stack frame and callee-saved registers.
    emitPrologue: *const fn (
        *std.io.AnyWriter,
        allocated_size: usize,
        clobbered_callee_saved: []const regalloc.PhysicalReg,
    ) anyerror!void,

    /// Restore the stack frame and callee-saved registers, then returns.
    emitEpilogue: *const fn (
        *std.io.AnyWriter,
        allocated_size: usize,
        clobbered_callee_saved: []const regalloc.PhysicalReg,
    ) anyerror!void,
};

vtable: VTable,

/// in bytes
block_alignment: usize = 1,

/// in bytes
word_size: usize = 8,

preg_sizes: std.EnumMap(regalloc.RegClass, usize),

/// in bytes
stack_alignment: usize = 16,

pub fn emit(
    self: *Self,
    // allocator: std.mem.Allocator,
    func: *const MachineFunction,
    abi: Abi,
    regalloc_solution: *regalloc.SolutionConsumer,
    object: *Object,
) !void {
    const allocated_stack_size = func.getMaxAllocatedStackSize();
    const clobbered_callee_saved = abi.call_conv.callee_saved; //regalloc.getClobberedCalleeSaved(allocator, regalloc_solution.ranges, abi);

    // defer allocator.free(clobbered_callee_saved);

    try self.vtable.emitPrologue(object.code_buffer, allocated_stack_size, clobbered_callee_saved);

    var iter = func.blockIter();
    while (iter.next()) |block| {
        try self.emitBlock(block, regalloc_solution, &object.code_buffer);
    }

    try self.vtable.emitEpilogue(object.code_buffer, allocated_stack_size, clobbered_callee_saved);
}

fn emitBlock(
    self: *Self,
    block: MachineFunction.MachBlock,
    regalloc_solution: *regalloc.SolutionConsumer,
    buffer: *std.io.AnyWriter,
) !void {
    const required_padding = (self.block_alignment - self.buffer.offset % self.block_alignment) % self.block_alignment;
    try self.vtable.emitNops(buffer, required_padding);

    for (block.insts) |inst| {
        const solution_point = try regalloc_solution.advance();

        try self.emitStitches(solution_point.stitches);
        try inst.emit(buffer, solution_point.mapping);
    }
}

fn inferMovSize(self: Self, stitch: regalloc.Stitch) regalloc.RegisterSize {
    // NOTE: Stack-to-stack stitches should have been removed. This should panic otherwise.

    if (stitch.from == .stack) {
        return self.preg_sizes.getAssertContains(stitch.to.preg);
    }

    return self.preg_sizes.getAssertContains(stitch.from.preg);
}

fn emitStitches(
    self: *Self,
    buffer: *std.io.AnyWriter,
    stitches: []const regalloc.Stitch,
) !void {
    // const stitches = try solveParallelStitches(unordered_stitches);

    for (stitches) |stitch| {
        try self.vtable.emitStitch(buffer, stitch.from, stitch.to, self.inferMovSize(stitch));
    }
}
