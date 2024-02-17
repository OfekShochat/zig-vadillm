const std = @import("std");

const MachineFunction = @import("MachineFunction.zig");
const Buffer = @import("Buffer.zig");
const Object = @import("Object.zig");
const Abi = @import("Abi.zig");
const regalloc = @import("regalloc.zig");

const Self = @This();

pub const VTable = struct {
    emitNops: *const fn (*Buffer, n: usize) anyerror!void,
    emitMov: *const fn (*Buffer, from: regalloc.Allocation, to: regalloc.Allocation) anyerror!void,
    emitPrologue: *const fn (*Buffer) anyerror!void,
};

vtable: VTable,

/// in bytes
block_alignment: usize = 1,

/// in bytes
word_size: usize = 8,

pub fn emit(
    self: *Self,
    func: *const MachineFunction,
    regalloc_solution: *regalloc.SolutionConsumer,
    object: *Object,
) !void {
    try self.vtable.emitPrologue(object.code_buffer);

    var iter = func.blockIter();
    while (iter.next()) |block| {
        try self.emitBlock(block, regalloc_solution, &object.code_buffer);
    }
}

fn emitBlock(
    self: *Self,
    block: MachineFunction.MachBlock,
    regalloc_solution: *regalloc.SolutionConsumer,
    buffer: *Buffer,
) !void {
    const required_padding = (self.block_alignment - self.buffer.offset % self.block_alignment) % self.block_alignment;
    try self.vtable.emitNops(buffer, required_padding);

    for (block.insts) |inst| {
        const solution_point = try regalloc_solution.advance();

        try self.emitStitches(solution_point.stitches);
        try inst.emit(buffer, solution_point.mapping);
    }
}

fn emitStitches(
    self: *Self,
    buffer: *Buffer,
    stitches: []const regalloc.Stitch,
) !void {
    // const stitches = try solveParallelStitches(unordered_stitches);

    for (stitches) |stitch| {
        try self.vtable.emitMov(buffer, stitch.from, stitch.to);
    }
}
