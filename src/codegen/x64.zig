const std = @import("std");
const regalloc = @import("regalloc.zig");

const Target = @import("Target.zig");
const Buffer = @import("Buffer.zig");
const MachineInst = @import("MachineInst.zig");

pub const MemoryAddressing = struct {
    real: union(enum) {},
    stack_rel: usize,
};

pub fn emitNops(buffer: *Buffer, n: usize) !void {
    _ = buffer;
    _ = n;
}

pub fn emitMov(buffer: *Buffer, from: regalloc.Allocation, to: regalloc.Allocation) !void {
    _ = buffer;
    _ = from;
    _ = to;
}

pub fn emitStackReserve(buffer: *Buffer, size: usize) !void {
    try buffer.print("sub rsp, {}", .{size});
}

pub const Inst = union(enum) {
    mov_rr: struct { size: usize, src: regalloc.PhysicalReg, dst: regalloc.PhysicalReg },
    mov_mr: struct { size: usize, src: MemoryAddressing, dst: regalloc.PhysicalReg },

    pub fn emitNops(buffer: *Buffer, n: usize) Target.BufferError!void {
        for (0..n) |_| {
            try buffer.write(0x90);
        }
    }

    pub fn emitMov(buffer: *Buffer, from: regalloc.Allocation, to: regalloc.Allocation) Target.BufferError!void {
        const inst = switch (.{ from, to }) {
            .{ .stack, .preg } => {},
            .{ .stack, .stack } => {},
            .{ .preg, .stack } => {},
            .{ .preg, .preg } => {},
        };

        try inst.emit(buffer);
    }

    pub fn emitStackReserve(buffer: *Buffer, size: usize) !usize {
        _ = buffer;
        _ = size;
        return 1;
    }

    pub fn emitText(
        self: *Inst,
        buffer: *Buffer,
        mapping: *std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.LiveRange),
    ) !void {
        _ = self;
        _ = buffer;
        _ = mapping;
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

    pub fn machInstReadable(self: *Inst) MachineInst {
        return MachineInst{
            .vtable = MachineInst.VTable{
                .emit = self.emitText,
                .getAllocatableOperands = self.getAllocatableOperamnds,
            },
            .vptr = self,
        };
    }
};
