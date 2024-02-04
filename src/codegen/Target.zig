const std = @import("std");

const MachineFunction = @import("MachineFunction.zig");
const Buffer = @import("Buffer.zig");
const Object = @import("Object.zig");
const regalloc = @import("regalloc.zig");

const Self = @This();

pub const VTable = struct {
    emitNops: *const fn (*Buffer, usize) anyerror!void,
    emitMov: *const fn (*Buffer, regalloc.PhysicalReg, regalloc.PhysicalReg) anyerror!void,
};

vptr: *anyopaque,
vtable: VTable,
block_alignment: usize = 1,

pub fn emit(
    self: *Self,
    func: *const MachineFunction,
    regalloc_solution: *regalloc.SolutionConsumer,
    object: *Object,
) !void {
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
    const required_padding = self.buffer.offset % self.block_alignment;
    try self.vtable.emitNops(buffer, required_padding);

    for (block.insts) |inst| {
        const solution_point = try regalloc_solution.advance();

        for (solution_point.stitches) |stitch| {
            try self.vtable.emitMov(stitch.from, stitch.to);
        }

        try inst.emit(buffer, solution_point.mapping);
    }
}
