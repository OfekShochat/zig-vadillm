const std = @import("std");
const regalloc = @import("regalloc.zig");
const types = @import("../types.zig");

const Target = @import("Target.zig");
const MachineInst = @import("MachineInst.zig");
const Abi = @import("Abi.zig");

const word_size: regalloc.RegisterSize = .@"8";

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

const preg_sizes = blk: {
    var sizes = std.EnumMap(regalloc.RegClass, regalloc.RegisterSize){};

    sizes.put(.int, .@"8");
    sizes.put(.float, .@"8");
    sizes.put(.vector, .@"64");

    break :blk sizes;
};

pub const MemoryAddressing = struct {
    base: ?regalloc.PhysicalReg,
    index: ?regalloc.PhysicalReg = null,
    scale: u8 = 0,
    disp: i32 = 0,

    pub fn format(
        self: MemoryAddressing,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("[");

        if (self.base) |base| {
            // Registers here are not necessarily `word_size` bytes, but
            // for the sake of simplicity, we assume you don't use lower
            // bits for addressing. This is actually sane, because, for
            // example, `mov`s zero-extend. If this turns out as a stupid
            // design-choice, we can always use `std.fmt.Formatter` and
            // provide the size as context.
            try writer.print("{s} + ", .{getPregFromEncoding(base, word_size).?});
        }

        if (self.index) |index| {
            try writer.print("{s} * {} + ", .{ getPregFromEncoding(index, word_size).?, self.scale });
        }

        try writer.print("{}]", .{self.disp});
    }
};

pub fn emitNops(buffer: *std.io.AnyWriter, n: usize) !void {
    for (0..n) |_| {
        try buffer.writeAll("nop\n");
    }
}

fn getIntRegFromEncoding(encoding: u7, size: regalloc.RegisterSize) ?[]const u8 {
    return switch (encoding) {
        0 => switch (size) {
            .@"1" => "ah",
            .@"2" => "ax",
            .@"4" => "eax",
            .@"8" => "rax",
            else => @panic("Non existent register."),
        },
        1 => switch (size) {
            .@"1" => "cl",
            .@"2" => "cx",
            .@"4" => "ecx",
            .@"8" => "rcx",
            else => @panic("Non existent register."),
        },
        2 => switch (size) {
            .@"1" => "dl",
            .@"2" => "dx",
            .@"4" => "edx",
            .@"8" => "rdx",
            else => @panic("Non existent register."),
        },
        3 => switch (size) {
            .@"1" => "bl",
            .@"2" => "bx",
            .@"4" => "ebx",
            .@"8" => "rbx",
            else => @panic("Non existent register."),
        },
        4 => switch (size) {
            .@"1" => "spl",
            .@"2" => "sp",
            .@"4" => "esp",
            .@"8" => "rsp",
            else => @panic("Non existent register."),
        },
        // TODO: finish this
        else => null,
    };
}

fn getFloatRegFromEncoding(encoding: u7, size: regalloc.RegisterSize) ?[]const u8 {
    _ = encoding;
    _ = size;
    return "st0";
}

fn getVectorRegFromEncoding(encoding: u7, size: regalloc.RegisterSize) ?[]const u8 {
    _ = encoding;
    _ = size;
    return "xmm0";
}

fn getPregFromEncoding(preg: regalloc.PhysicalReg, size: regalloc.RegisterSize) ?[]const u8 {
    return switch (preg.class) {
        .int => getIntRegFromEncoding(preg.encoding, size),
        .float => getFloatRegFromEncoding(preg.encoding, size),
        .vector => getVectorRegFromEncoding(preg.encoding, size),
    };
}

pub fn emitMov(buffer: *std.io.AnyWriter, from: regalloc.Allocation, to: regalloc.Allocation, size: regalloc.RegisterSize) !void {
    try buffer.writeAll("mov ");

    switch (from) {
        .stack => |offset| try buffer.print("[rsp + {}]", .{offset.?}),
        .preg => |preg| try buffer.writeAll(getPregFromEncoding(preg, size).?),
    }

    try buffer.writeAll(", ");

    switch (to) {
        .stack => |offset| try buffer.print("[rsp + {}]", .{offset.?}),
        .preg => |preg| try buffer.writeAll(getPregFromEncoding(preg, size).?),
    }
}

pub fn emitStackReserve(buffer: *std.io.AnyWriter, size: usize) !void {
    try buffer.print("sub rsp, {}", .{size});
}

pub fn formatAllocation(
    self: regalloc.Allocation,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    return switch (self) {
        .preg => |preg| writer.writeAll(getPregFromEncoding(preg, preg_sizes.getAssertContains(preg.class)).?),
        .stack => |offset| MemoryAddressing.format(
            .{ .base = rsp, .disp = @intCast(offset.?) },
            fmt,
            options,
            writer,
        ),
    };
}

fn fmtAllocation(allocation: regalloc.Allocation) std.fmt.Formatter(formatAllocation) {
    return .{ .data = allocation };
}

pub const Inst = union(enum) {
    // this doesn't make sense register allocation wise
    mov_rr: struct { size: regalloc.RegisterSize, src: regalloc.PhysicalReg, dst: regalloc.PhysicalReg },
    mov_mr: struct { size: regalloc.RegisterSize, src: MemoryAddressing, dst: regalloc.PhysicalReg },
    mov_rm: struct { size: regalloc.RegisterSize, src: regalloc.PhysicalReg, dst: MemoryAddressing },
    mov_imm32: struct { size: regalloc.RegisterSize, imm32: u32, dst: regalloc.PhysicalReg },
    mov_vr: struct { size: regalloc.RegisterSize, src: regalloc.VirtualReg, dst: regalloc.PhysicalReg },
    mov: struct { size: regalloc.RegisterSize, src: regalloc.VirtualReg, dst: regalloc.VirtualReg },
    add: struct {
        size: regalloc.RegisterSize,
        lhs: regalloc.VirtualReg,
        rhs: regalloc.VirtualReg,
        dst: regalloc.VirtualReg,
    },
    ret: ?regalloc.VirtualReg,
    syscall: struct {
        id: u32,
        values: []const regalloc.VirtualReg,
    },
    push: struct { size: regalloc.RegisterSize, src: regalloc.VirtualReg },
    push_imm32: u32,

    pub fn emitText(
        self: *const Inst,
        buffer: *std.io.AnyWriter,
        abi: Abi,
        mapping: std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.Allocation),
    ) !void {
        switch (self.*) {
            .mov_rr => |mov_rr| try buffer.print("  mov {s}, {s}\n", .{
                getPregFromEncoding(mov_rr.dst, mov_rr.size).?,
                getPregFromEncoding(mov_rr.src, mov_rr.size).?,
            }),
            .mov_mr => |mov_mr| try buffer.print("  mov {s}, {}\n", .{
                getPregFromEncoding(mov_mr.dst, mov_mr.size).?,
                mov_mr.src,
            }),
            .mov_rm => |mov_rm| try buffer.print("  mov {}, {s}\n", .{
                mov_rm.dst,
                getPregFromEncoding(mov_rm.src, mov_rm.size).?,
            }),
            .mov => |mov| try buffer.print("  mov {}, {}\n", .{
                fmtAllocation(mapping.get(mov.dst).?),
                fmtAllocation(mapping.get(mov.src).?),
            }),
            .mov_vr => |mov_vr| try buffer.print("  mov {s}, {}\n", .{
                getPregFromEncoding(mov_vr.dst, mov_vr.size).?,
                fmtAllocation(mapping.get(mov_vr.src).?),
            }),
            .mov_imm32 => |mov| try buffer.print("  mov {s}, {}\n", .{
                getPregFromEncoding(mov.dst, mov.size).?,
                mov.imm32,
            }),
            .add => |add| try buffer.print("  add {s}, {s}\n", .{
                getPregFromEncoding(mapping.get(add.dst).?.preg, add.size).?,
                getPregFromEncoding(mapping.get(add.rhs).?.preg, add.size).?,
            }),
            .ret => |value| if (value) |vreg| {
                // TODO: optimizations of bigger structures.
                try (Inst{ .mov_vr = .{
                    .src = vreg,
                    .dst = rax,
                    .size = word_size,
                } }).emitText(buffer, abi, mapping);

                try buffer.writeAll("  ret\n");
            },
            .push => |push| try buffer.print("  push {s}\n", .{
                getPregFromEncoding(mapping.get(push.src).?.preg, push.size).?,
            }),
            .push_imm32 => |imm32| try buffer.print("  push {}\n", .{imm32}),
            .syscall => |syscall| {
                if (abi.call_conv.params.len > 0) {
                    try (Inst{ .mov_imm32 = .{
                        .imm32 = syscall.id,
                        .dst = abi.call_conv.params[0],
                        .size = word_size,
                    } }).emitText(buffer, abi, mapping);
                } else {
                    try (Inst{ .push_imm32 = syscall.id }).emitText(buffer, abi, mapping);
                }

                var handled: usize = 0;

                while (handled + 1 < abi.call_conv.params.len) : (handled += 1) {
                    try (Inst{ .mov_vr = .{
                        .src = syscall.values[handled],
                        .dst = abi.call_conv.params[handled + 1],
                        .size = word_size,
                    } }).emitText(buffer, abi, mapping);
                }

                for (syscall.values[handled..]) |value| {
                    // TODO: this shouldn't be `word_size`'d.
                    try (Inst{ .push = .{
                        .src = value,
                        .size = value.typ.containingRegisterSize(),
                    } }).emitText(buffer, abi, mapping);
                }

                try buffer.writeAll("  syscall\n");
            },
        }
    }

    pub fn getAllocatableOperands(self: *Inst, operands_out: *std.ArrayList(regalloc.Operand)) !void {
        _ = operands_out;

        switch (self.*) {
            .mov_rr,
            .mov_mr,
            .mov_rm,
            => {},
        }
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

test "emit" {
    const allocator = std.testing.allocator;

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var gwriter = buffer.writer();
    var writer = gwriter.any();

    const abi = Abi{
        // The pregs should not be in the abi, probably.
        .int_pregs = null,
        .float_pregs = null,
        .vector_pregs = null,
        .call_conv = .{
            .params = &.{
                // regalloc.PhysicalReg{ .class = .int, .encoding = 0 },
            },
            .callee_saved = &.{},
        },
    };

    const insts: []const Inst = &.{
        Inst{ .mov_mr = .{ .src = MemoryAddressing{
            .base = rsp,
            .index = rax,
            .scale = 8,
            .disp = 3,
        }, .dst = rax, .size = .@"8" } },
        Inst{ .mov_rr = .{ .src = rax, .dst = rbx, .size = .@"4" } },
        Inst{ .syscall = .{ .id = 0, .values = &.{regalloc.VirtualReg{ .typ = types.I32, .index = 0 }} } },
    };

    var mapping = std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.Allocation).init(allocator);
    defer mapping.deinit();

    try mapping.put(regalloc.VirtualReg{ .typ = types.I32, .index = 0 }, .{ .preg = rbx });

    for (insts) |inst| {
        try inst.emitText(&writer, abi, mapping);
    }

    std.debug.print("{s}\n", .{buffer.items});
}
