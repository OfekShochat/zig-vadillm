const std = @import("std");
const regalloc = @import("regalloc.zig");
const codegen = @import("../codegen.zig");

const Abi = @import("Abi.zig");
const MachineInst = @import("MachineInst.zig");
const CodePoint = @import("CodePoint.zig");

const MachineFunction = @This();

pub const MachBlock = struct {
    id: codegen.Index,
    start: CodePoint,
    end: CodePoint,
    insts: []const MachineInst,
};

pub const BlockHeader = struct {
    start: CodePoint,
    end: CodePoint,
};

num_virtual_regs: usize,
// ordered by start
block_headers: []const BlockHeader,
params: []const regalloc.VirtualReg,
insts: []const MachineInst,

pub fn getInst(self: MachineFunction, point: CodePoint) ?MachineInst {
    const index = point.toArrayIndex();
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
        .end = header.end,
        .insts = self.insts[header.start.toArrayIndex() .. header.end.toArrayIndex() + 1],
    };
}

// This duplicates computation with regalloc.
pub fn getMaxAllocatedStackSize(self: MachineFunction) usize {
    var current_stack_offset: isize = 0;
    var max_stack_offset: isize = 0;

    for (self.insts) |inst| {
        std.debug.assert(current_stack_offset >= 0);

        current_stack_offset += inst.getStackDelta();
        if (current_stack_offset > max_stack_offset) {
            max_stack_offset = current_stack_offset;
        }
    }

    return @intCast(max_stack_offset);
}

fn blockHeadersCompare(_: void, lhs: BlockHeader, rhs: BlockHeader) std.math.Order {
    return lhs.start.compare(rhs.start);
}

pub fn getBlockAt(self: MachineFunction, code_point: CodePoint) ?MachBlock {
    const block_id = std.sort.binarySearch(
        BlockHeader,
        code_point.point,
        self.block_headers,
        void{},
        blockHeadersCompare,
    ) orelse return null;

    const header = self.block_headers.items[block_id];

    return MachBlock{
        .id = block_id,
        .start = header.start,
        .insts = self.insts[header.start.toArrayIndex()..header.end.toArrayIndex()],
    };
}

pub fn getInstsFrom(self: MachineFunction, from: CodePoint, to: CodePoint) []const MachineInst {
    return self.insts[from.toArrayIndex()..to.toArrayIndex()];
}

pub fn blockIter(self: *const MachineFunction) BlockIter {
    return BlockIter{ .func = self };
}

pub fn reverseBlockIter(self: *const MachineFunction) ReverseBlockIter {
    return ReverseBlockIter{ .func = self };
}

pub const BlockIter = struct {
    func: *const MachineFunction,
    index: codegen.Index = 0,

    pub fn next(self: *BlockIter) ?MachBlock {
        defer self.index += 1;

        return self.func.getBlock(self.index);
    }
};

pub const ReverseBlockIter = struct {
    func: *const MachineFunction,
    index: codegen.Index = 1,

    pub fn next(self: *ReverseBlockIter) ?MachBlock {
        if (self.index > self.func.block_headers.len)
            return null;

        defer self.index += 1;

        return self.func.getBlock(@intCast(self.func.block_headers.len - self.index));
    }
};
