const std = @import("std");

const regalloc = @import("regalloc.zig");
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
    operands: []const codegen.Index,
};

// pub const TerminatorData = union(enum) {
//     unconditional: BlockCall,
//     conditional: PooledVector(BlockCall),
// };

pub const MachBlock = struct {
    start: codegen.Index,
    params: []const regalloc.VirtualReg,
    insts: []const MachineInst,
    succ_phis: []const BlockCall,
    // terminator_data: TerminatorData,
};

const BlockHeader = struct {
    start: codegen.Index,
    end: codegen.Index,
    succ_phis: []const BlockCall,
    params: []const regalloc.VirtualReg,
};

num_virtual_regs: usize,
block_headers: []const BlockHeader,
// blocks: std.ArrayList(MachBlock),
insts: []const MachineInst,
// vregs: std.ArrayList(codegen.regalloc.VirtualReg),

pub fn getBlock(self: MachineFunction, block_id: codegen.Index) ?MachBlock {
    if (block_id >= self.block_headers.len) {
        return null;
    }

    const header = self.block_headers.items[block_id];

    return MachBlock{
        .start = header.start,
        .params = header.params,
        .insts = self.insts[header.start..header.end],
        .succ_phis = header.succ_phis,
    };
}
