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

pub const systemv_abi = Abi{
    .int_pregs = &.{ rax, rbx, rcx, rdx, rdi, rsi, r8, r9, r10, r11, r12, r13, r14, r15 },
    .float_pregs = &.{ st0, st1, st2, st3, st4, st5, st6, st7 },
    .vector_pregs = &.{zmm0},
    .call_conv = .{
        .params = &.{ rdi, rsi, rdx, rcx, r8, r9 },
        .syscall_params = &.{ rax, rdi, rsi, rdx, r10, r8, r9 },
        .callee_saved = &.{ rbp, rbx, r12, r13, r14, r15 },
    },
};

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
        5 => switch (size) {
            .@"1" => "bpl",
            .@"2" => "bp",
            .@"4" => "ebp",
            .@"8" => "rbp",
            else => @panic("Non existent register."),
        },
        6 => switch (size) {
            .@"1" => "dh",
            .@"2" => "si",
            .@"4" => "esi",
            .@"8" => "rsi",
            else => @panic("Non existent register."),
        },
        7 => switch (size) {
            .@"1" => "bh",
            .@"2" => "di",
            .@"4" => "edi",
            .@"8" => "rdi",
            else => @panic("Non existent register."),
        },
        12 => switch (size) {
            .@"1" => "r12b",
            .@"2" => "r12w",
            .@"4" => "r12d",
            .@"8" => "r12",
            else => @panic("Non existent register."),
        },
        13 => switch (size) {
            .@"1" => "r13b",
            .@"2" => "r13w",
            .@"4" => "r13d",
            .@"8" => "r13",
            else => @panic("Non existent register."),
        },
        14 => switch (size) {
            .@"1" => "r14b",
            .@"2" => "r14w",
            .@"4" => "r14d",
            .@"8" => "r14",
            else => @panic("Non existent register."),
        },
        15 => switch (size) {
            .@"1" => "r15b",
            .@"2" => "r15w",
            .@"4" => "r15d",
            .@"8" => "r15",
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

// Returns the first-containing vector register for `size`.
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

pub fn emitMov(buffer: *std.io.AnyWriter, from: regalloc.Allocation, to: regalloc.Allocation) !void {
    try buffer.print("  mov {}, {}\n", .{ fmtAllocation(to), fmtAllocation(from) });
}

pub fn emitStackReserve(buffer: *std.io.AnyWriter, size: usize) !void {
    try buffer.print("  sub rsp, {}\n", .{size});
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

fn selectMovInst(src_size: regalloc.RegisterSize) []const u8 {
    return switch (src_size) {
        .@"4" => "movl",
        .@"8" => "movq",
        else => unreachable,
    };
}

pub const Inst = union(enum) {
    mov_rr: struct { size: regalloc.RegisterSize, src: regalloc.PhysicalReg, dst: regalloc.PhysicalReg },
    mov_mr: struct { size: regalloc.RegisterSize, src: MemoryAddressing, dst: regalloc.PhysicalReg },
    mov_rm: struct { size: regalloc.RegisterSize, src: regalloc.PhysicalReg, dst: MemoryAddressing },
    mov_iv: struct { imm: u64, dst: regalloc.VirtualReg },
    mov_vr: struct { size: regalloc.RegisterSize, src: regalloc.VirtualReg, dst: regalloc.PhysicalReg },
    mov: struct { size: regalloc.RegisterSize, src: regalloc.VirtualReg, dst: regalloc.VirtualReg },
    add: struct {
        size: regalloc.RegisterSize,
        lhs: regalloc.VirtualReg,
        rhs: regalloc.VirtualReg,
        dst: regalloc.VirtualReg,
    },
    ret: []const regalloc.VirtualReg,
    syscall: []const regalloc.VirtualReg,
    push: struct { size: regalloc.RegisterSize, src: regalloc.VirtualReg },
    pop: struct { size: regalloc.RegisterSize, dst: regalloc.VirtualReg },
    push_imm32: u32,

    fn emitTextInterface(
        self: *const anyopaque,
        buffer: *std.io.AnyWriter,
        mapping: *const std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.Allocation),
    ) anyerror!void {
        return emitText(@ptrCast(@alignCast(self)), buffer, mapping);
    }

    pub fn emitText(
        self: *const Inst,
        buffer: *std.io.AnyWriter,
        mapping: *const std.AutoArrayHashMap(regalloc.VirtualReg, regalloc.Allocation),
    ) !void {
        switch (self.*) {
            // TODO: infer movq/mov/movl for xmm registers etc
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
            // TODO: how do I model reg->mem movs that are into an address pointed by a vreg?
            .mov => |mov| try buffer.print("  mov {}, {}\n", .{
                fmtAllocation(mapping.get(mov.dst).?),
                fmtAllocation(mapping.get(mov.src).?),
            }),
            .mov_vr => |mov_vr| try buffer.print("  mov {s}, {}\n", .{
                getPregFromEncoding(mov_vr.dst, mov_vr.size).?,
                fmtAllocation(mapping.get(mov_vr.src).?),
            }),
            .mov_iv => |mov| try buffer.print("  mov {s}, {}\n", .{
                fmtAllocation(mapping.get(mov.dst).?),
                mov.imm,
            }),
            .add => |add| try buffer.print("  add {s}, {s}\n", .{
                getPregFromEncoding(mapping.get(add.dst).?.preg, add.size).?,
                getPregFromEncoding(mapping.get(add.rhs).?.preg, add.size).?,
            }),
            .ret => try buffer.writeAll("  ret\n"),
            .push => |push| try buffer.print("  push {s}\n", .{
                getPregFromEncoding(mapping.get(push.src).?.preg, push.size).?,
            }),
            .pop => |pop| try buffer.print("  pop {s}\n", .{
                getPregFromEncoding(mapping.get(pop.dst).?.preg, pop.size).?,
            }),
            .push_imm32 => |imm32| try buffer.print("  push {}\n", .{imm32}),
            .syscall => try buffer.writeAll("  syscall\n"),
        }
    }

    pub fn getAllocatableOperands(ctx: *const anyopaque, abi: Abi, operands_out: *std.ArrayList(regalloc.Operand)) !void {
        const self: *const Inst = @ptrCast(@alignCast(ctx));

        switch (self.*) {
            .mov_rr,
            .mov_mr,
            .mov_rm,
            => {},
            .mov => |mov| {
                try operands_out.append(regalloc.Operand.init(mov.src, .use, .none, .early));
                // hm, conditional constraints (mem->mem is disallowed)?
                try operands_out.append(regalloc.Operand.init(mov.dst, .def, .none, .late));
            },
            .add => |add| {
                try operands_out.append(regalloc.Operand.init(add.lhs, .use, .phys_reg, .early));
                try operands_out.append(regalloc.Operand.init(add.rhs, .use, .phys_reg, .early));
                // let the liveness put it in the same interval (it shouldn't be able to split in the middle of the instruction)
                try operands_out.append(regalloc.Operand.init(add.dst, .def, .{ .reuse = 0 }, .late));
            },
            .mov_iv => |mov| try operands_out.append(regalloc.Operand.init(mov.dst, .def, .none, .late)),
            .syscall => |values| {
                const syscall_params = abi.call_conv.syscall_params;
                var idx: usize = 0;

                while (idx < values.len) : (idx += 1) {
                    const constraint: regalloc.LocationConstraint = if (idx < syscall_params.len)
                        .{ .fixed_reg = syscall_params[idx] }
                    else
                        .stack;

                    try operands_out.append(regalloc.Operand.init(values[idx], .use, constraint, .early));
                }
            },
            // .ret => |values| ,
            else => {},
        }
    }

    fn emitPrologueText(
        buffer: *std.io.AnyWriter,
        allocated_size: usize,
        clobbered_callee_saved: []const regalloc.PhysicalReg,
    ) !void {
        for (clobbered_callee_saved) |preg| {
            try buffer.print("  push {s}\n", .{getPregFromEncoding(
                preg,
                preg_sizes.getAssertContains(preg.class),
            ).?});
        }

        try buffer.print(
            \\  mov rbp, rsp
            \\  sub rsp, {}
            \\
        , .{allocated_size});
    }

    pub fn emitEpilogueText(
        buffer: *std.io.AnyWriter,
        allocated_size: usize,
        clobbered_callee_saved: []const regalloc.PhysicalReg,
    ) !void {
        try buffer.print("  add rsp, {}\n", .{allocated_size});

        var iter = std.mem.reverseIterator(clobbered_callee_saved);
        while (iter.next()) |preg| {
            try buffer.print("  pop {s}\n", .{getPregFromEncoding(
                preg,
                preg_sizes.getAssertContains(preg.class),
            ).?});
        }

        try buffer.writeAll(
            \\  mov rsp, rbp
            \\  ret
            \\
        );
    }

    pub fn getStackDeltaInterface(self: *const anyopaque) isize {
        _ = self;
        return 0;
    }

    fn clobbers(ctx: *const anyopaque, preg: regalloc.PhysicalReg) bool {
        const self: *const Inst = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = preg;

        return false;
    }

    // pub fn machInst(self: *const Inst) MachineInst {
    //     return MachineInst{
    //         .vtable = MachineInst.VTable{
    //             .emit = emit,
    //             .getAllocatableOperands = getAllocatableOperands,
    //         },
    //         .vptr = self,
    //     };
    // }

    pub fn machInstReadable(self: *const Inst) MachineInst {
        return MachineInst{
            .vtable = MachineInst.VTable{
                .clobbers = clobbers,
                .emit = emitTextInterface,
                .getAllocatableOperands = getAllocatableOperands,
                .getStackDelta = getStackDeltaInterface,
            },
            .vptr = @ptrCast(self),
        };
    }
};

const MachineFunction = @import("MachineFunction.zig");

test "emit" {
    const allocator = std.testing.allocator;

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var gwriter = buffer.writer();
    const writer = gwriter.any();

    const abi = systemv_abi;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const insts: []const Inst = &.{
        Inst{ .mov_mr = .{ .src = MemoryAddressing{
            .base = rsp,
            .index = rbx,
            .scale = 8,
            .disp = 3,
        }, .dst = rax, .size = .@"8" } },
        Inst{ .mov_iv = .{ .imm = 60, .dst = regalloc.VirtualReg{ .typ = types.I32, .index = 0 } } },
        Inst{ .mov_iv = .{ .imm = 32, .dst = regalloc.VirtualReg{ .typ = types.I32, .index = 1 } } },
        Inst{
            .syscall = &.{
                regalloc.VirtualReg{ .typ = types.I32, .index = 0 },
                regalloc.VirtualReg{ .typ = types.I32, .index = 1 },
            },
        },
        Inst{ .mov = .{
            .src = regalloc.VirtualReg{ .typ = types.I32, .index = 1 },
            .dst = regalloc.VirtualReg{ .typ = types.I32, .index = 2 },
            .size = .@"8",
        } },
        Inst{ .ret = &.{regalloc.VirtualReg{ .typ = types.I32, .index = 0 }} },
    };

    var mach_insts = try allocator.alloc(MachineInst, insts.len);
    defer allocator.free(mach_insts);

    for (insts, 0..) |*inst, i| {
        mach_insts[i] = inst.machInstReadable();
    }

    const func = MachineFunction{
        .insts = mach_insts,
        .params = &.{},
        .block_headers = &.{
            MachineFunction.BlockHeader{
                .start = .{ .point = 0 },
                .end = .{ .point = 8 },
            },
        },
        .num_virtual_regs = 3,
    };

    var target = Target{
        .vtable = Target.VTable{
            .emitNops = emitNops,
            .emitStitch = emitMov,
            .emitPrologue = Inst.emitPrologueText,
            .emitEpilogue = Inst.emitEpilogueText,
        },
    };

    const Object = @import("Object.zig");
    var object = Object{
        .context = undefined,
        .code_buffer = writer,
        .const_buffer = undefined,
        .symtab = undefined,
    };

    var cfg = @import("../ControlFlowGraph.zig"){ .entry_ref = 0 };
    defer cfg.deinit(allocator);
    try cfg.nodes.put(allocator, 0, @import("../ControlFlowGraph.zig").CFGNode{ .preds = .{}, .succs = .{} });
    try cfg.computePostorder(allocator);

    const solution = try regalloc.runRegalloc(@import("BacktrackingAllocator.zig"), &arena, &cfg, abi, &func, target);

    var consumer = regalloc.SolutionConsumer.init(allocator, solution);
    defer consumer.deinit();

    try target.emit(allocator, &func, &consumer, abi, &object);
    std.debug.print("{s}\n", .{buffer.items});

    // TODO: reconsider the epilogues (glibc or not glibc?) This is about the ABI thing / lowering whatever

    try std.testing.expectEqualStrings(
        \\  push rbx
        \\  mov rbp, rsp
        \\  sub rsp, 10
        \\  mov rax, [rsp + rbx * 8 + 3]
        \\  mov rax, 60
        \\  mov rdi, 32
        \\  syscall
        \\  add rsp, 10
        \\  pop rbx
        \\  mov rsp, rbp
        \\  ret
        \\
    , buffer.items);
}
