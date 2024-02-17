const std = @import("std");
const regalloc = @import("regalloc.zig");

const Target = @import("Target.zig");
const Buffer = @import("Buffer.zig");
const MachineInst = @import("MachineInst.zig");

const rax = regalloc.PhysicalReg{ .class = .int, .encoding = 0 };
const rcx = regalloc.PhysicalReg{ .class = .int, .encoding = 1 };
const rdx = regalloc.PhysicalReg{ .class = .int, .encoding = 2 };
const rbx = regalloc.PhysicalReg{ .class = .int, .encoding = 3 };
const rsp = regalloc.PhysicalReg{ .class = .int, .encoding = 4 };
const rbp = regalloc.PhysicalReg{ .class = .int, .encoding = 5 };
const rsi = regalloc.PhysicalReg{ .class = .int, .encoding = 6 };
const rdi = regalloc.PhysicalReg{ .class = .int, .encoding = 7 };
const r8 = regalloc.PhysicalReg{ .class = .int, .encoding = 8 };
const r9 = regalloc.PhysicalReg{ .class = .int, .encoding = 9 };
const r10 = regalloc.PhysicalReg{ .class = .int, .encoding = 10 };
const r11 = regalloc.PhysicalReg{ .class = .int, .encoding = 11 };
const r12 = regalloc.PhysicalReg{ .class = .int, .encoding = 12 };
const r13 = regalloc.PhysicalReg{ .class = .int, .encoding = 13 };
const r14 = regalloc.PhysicalReg{ .class = .int, .encoding = 14 };
const r15 = regalloc.PhysicalReg{ .class = .int, .encoding = 15 };

const st0 = regalloc.PhysicalReg{ .class = .float, .encoding = 0 };
const st1 = regalloc.PhysicalReg{ .class = .float, .encoding = 1 };
const st2 = regalloc.PhysicalReg{ .class = .float, .encoding = 2 };
const st3 = regalloc.PhysicalReg{ .class = .float, .encoding = 3 };
const st4 = regalloc.PhysicalReg{ .class = .float, .encoding = 4 };
const st5 = regalloc.PhysicalReg{ .class = .float, .encoding = 4 };
const st6 = regalloc.PhysicalReg{ .class = .float, .encoding = 6 };
const st7 = regalloc.PhysicalReg{ .class = .float, .encoding = 7 };

// ymm and xmm are contained here
const zmm0 = regalloc.PhysicalReg{ .class = .vector, .encoding = 0 };

pub const MemoryAddressing = struct {
    base: regalloc.PhysicalReg,
    index: regalloc.PhysicalReg,
    scale: u32,
    imm: u32,
};

pub fn emitNops(buffer: *Buffer, n: usize) !void {
    for (0..n) |_| {
        try buffer.writeAll("nop\n");
    }
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
