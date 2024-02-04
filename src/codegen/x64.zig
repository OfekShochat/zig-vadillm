const std = @import("std");
const regalloc = @import("regalloc.zig");

const Target = @import("Target.zig");
const Buffer = @import("Buffer.zig");
const MachineInst = @import("MachineInst.zig");

pub const Inst = union(enum) {
    pub fn emitNops(buffer: *Buffer, n: usize) Target.BufferError!void {
        for (0..n) |_| {
            try buffer.write(0x90);
        }
    }

    pub fn emitMov(buffer: *Buffer, from: regalloc.Allocation, to: regalloc.Allocation) Target.BufferError!void {
        _ = buffer;
        _ = from;
        _ = to;
    }

    pub fn machInst(self: *Inst) MachineInst {
        return MachineInst{
            .vtable = MachineInst.VTable{
                .emit = self.emit,
                .getAllocatableOperands = self.getAllocatableOperamnds,
            },
            .vptr = self,
        };
    }
};
