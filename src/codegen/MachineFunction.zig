const std = @import("std");

const codegen = @import("../codegen.zig");
const Index = codegen.Index;
const MachineInst = @import("MachineInst.zig");

const MachineFunction = @This();

const BlockRange = struct {
    start: usize,
    end: usize,
};

insts: std.ArrayList(MachineInst),
blocks: std.ArrayList(BlockRange),
vregs: std.ArrayList(codegen.regalloc.VirtualReg),

pub fn instructionsFor(self: MachineFunction, block: Index) ?[]const MachineInst {
    if (block >= self.blocks.items.len) {
        return null;
    }

    const block_range = self.blocks.items[block];
    return self.insts.items[block_range.start..block_range.end];
}

pub fn getTerminator(self: MachineFunction, block: Index) MachineInst {
    if (block >= self.blocks.items.len) {
        return null;
    }

    const block_range = self.blocks.items[block];
    return self.insts.items[block_range.end];
}

pub fn getBlockByInst(self: MachineFunction, instIdx: Index) Index {
    if(self.insts > self.insts.items.len) {
        return null;
    }

    for (self.blocks.items.len) |block_idx| {
        if(instIdx > self.blocks[block_idx].start and instIdx < self.blocks[block_idx].end) {
            return block_idx;
        }
    }
}

pub fn addBlock(self: MachineFunction, new_block: *std.ArrayListUnmanaged) {
    BlockRange lastBlock = blocks.getLast();
    usize start_of_new_block = lastBlock.end + 1;
    insts = concatenateArrayLists(insts, new_block);
    blocks.append(BlockRange{.start = start_of_new_block, .end = start_of_new_block + new_block.items.len});
}

fn concatenateArrayLists(combineTo: *std.ArrayList(comptime T), appendFrom: *std.ArrayList(comptime T) !T) T {
    while (appendFrom.items.len > 0) : (comptime appendFrom.items.len > 0) {
        const element = appendFrom.items[0];
        _ = combineTo.append(element);
        _ = appendFrom.items.pop();
    }
}