const std = @import("std");

const regalloc = @import("regalloc.zig");
const codegen = @import("codegen.zig");
const MachineInst = @import("MachineInst.zig");

const MachineFunction = @This();

pub const MachBlock = struct {
    id: codegen.Index,
    start: codegen.CodePoint,
    insts: []const MachineInst,
};

const BlockHeader = struct {
    start: codegen.CodePoint,
    end: codegen.CodePoint,
};

num_virtual_regs: usize,
// ordered by start
block_headers: []const BlockHeader,
insts: []const MachineInst,

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

    const header = self.block_headers[block_id];

    return MachBlock{
        .id = block_id,
        .start = header.start,
        .insts = self.insts[header.start.point..header.end.point],
    };
}

fn blockHeadersCompareFn(_: void, lhs: BlockHeader, rhs: BlockHeader) std.math.Order {
    return lhs.start.compareFn(rhs.start);
}

pub fn getBlockAt(self: MachineFunction, code_point: codegen.CodePoint) ?MachBlock {
    const block_id = std.sort.binarySearch(
        BlockHeader,
        code_point.point,
        self.block_headers,
        void{},
        blockHeadersCompareFn,
    ) orelse return null;

    const header = self.block_headers.items[block_id];

    return MachBlock{
        .id = block_id,
        .start = header.start,
        .insts = self.insts[header.start..header.end],
    };
}

pub fn getInstsFrom(self: MachineFunction, from: codegen.CodePoint, to: codegen.CodePoint) []const MachineInst {
    return self.insts[from.toArrayIndex()..to.toArrayIndex()];
}

pub fn blockIter(self: *const MachineFunction) BlockIter {
    return BlockIter{ .func = self };
}

pub const BlockIter = struct {
    func: *const MachineFunction,
    index: codegen.Index = 0,

    pub fn next(self: *BlockIter) ?MachBlock {
        defer self.index += 1;

        return self.func.getBlock(self.index);
    }
};
