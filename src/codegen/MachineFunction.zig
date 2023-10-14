const std = @import("std");

const codegen = @import("../codegen.zig");
const MachineInst = @import("MachineInst.zig");
const PooledVector = @import("../list_pool.zig").PooledVector;

const MachineFunction = @This();

const BlockRange = struct {
    start: usize,
    end: usize,
};

pub const BlockCall = struct {
    // first operand is the block index, the others are vregs.
    operands: PooledVector(codegen.Index),
};

pub const TerminatorData = union(enum) {
    unconditional: BlockCall,
    conditional: PooledVector(BlockCall),
};

pub const MachBlock = struct {
    insts: []const MachineInst,
    terminator_data: TerminatorData,
};

blocks: std.ArrayList(MachBlock),
// vregs: std.ArrayList(codegen.regalloc.VirtualReg),

pub fn getBlock(self: MachineFunction, block_id: codegen.Index) ?*MachBlock {
    if (block_id >= self.block.items.len) {
        return null;
    }

    return self.block.items[block_id];
}
