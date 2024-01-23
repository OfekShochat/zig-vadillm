const std = @import("std");

const regalloc = @import("regalloc.zig");
const codegen = @import("../codegen.zig");
const MachineInst = @import("MachineInst.zig");
const PooledVector = @import("../list_pool.zig").PooledVector;

const MachineFunction = @This();

pub const BlockCall = struct {
    block: codegen.Index,
    operands: []const codegen.Index, // VirtualReg?
};

pub const MachBlock = struct {
    id: codegen.Index,
    start: codegen.Index,
    // params: []const regalloc.VirtualReg,
    insts: []const MachineInst,
    // succ_phis: []const BlockCall,
};

const BlockHeader = struct {
    start: codegen.Index,
    end: codegen.Index,
    // succ_phis: []const BlockCall,
    // params: []const regalloc.VirtualReg,
};

num_virtual_regs: usize,
block_headers: []const BlockHeader,
// blocks: std.ArrayList(MachBlock),
insts: []const MachineInst,
// vregs: std.ArrayList(codegen.regalloc.VirtualReg),

pub fn getInst(self: MachineFunction, index: codegen.Index) ?MachineInst {
    if (index >= self.insts.len) {
        return null;
    }

    return self.insts[index];
}

pub fn getBlock(self: MachineFunction, block_id: codegen.Index) ?MachBlock {
    if (block_id >= self.block_headers.len) {
        return null;
    }

    const header = self.block_headers.items[block_id];

    return MachBlock{
        .id = block_id,
        .start = header.start,
        .insts = self.insts[header.start..header.end],
    };
}

pub fn blockIter(self: *const MachineFunction) BlockIter {
    return BlockIter{
        .func = self,
    };
}

pub const BlockIter = struct {
    func: *const MachineFunction,
    index: usize = 0,

    pub fn next(self: *BlockIter) ?MachBlock {
        defer self.index += 1;

        return self.func.getBlock(self.index);
    }
};
