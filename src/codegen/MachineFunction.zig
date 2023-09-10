const std = @import("std");

const ir = @import("../ir.zig");
const MachineInst = @import("MachineInst.zig");

const MachineFunction = @This();

const BlockRange = struct {
    start: usize,
    end: usize,
};

insts: std.ArrayListUnmanaged(MachineInst),
blocks: std.ArrayListUnmanaged(BlockRange),

pub fn instructionsFor(self: MachineFunction, block: ir.Index) ?[]const MachineInst {
    if (block >= self.blocks.items.len) {
        return null;
    }

    const block_range = self.blocks.items[block];
    return self.insts.items[block_range.start..block_range.end];
}
