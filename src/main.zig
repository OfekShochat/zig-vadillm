const std = @import("std");
const types = @import("../types.zig");

const Target = @import("Target.zig");
const MachineInst = @import("MachineInst.zig");
const Abi = @import("Abi.zig");

pub fn main() !void {
    const allocator =std.heap.page_allocator;

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var gwriter = buffer.writer();
    const writer = gwriter.any();

    // TODO: have preferred and not-preferred regs within the allocator (callee-saved regs for example)
    // if a reg is used from the non-preferred regs, it is moved to the preferred regs. see, callee-saved
    // regs.

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
        .code_buffer = writer,
        .const_buffer = undefined,
        .symtab = undefined,
    };

    var cfg = @import("../ControlFlowGraph.zig"){ .entry_ref = 0 };
    defer cfg.deinit(allocator);
    try cfg.nodes.put(allocator, 0, @import("../ControlFlowGraph.zig").CFGNode{ .preds = .{}, .succs = .{} });
    try cfg.computePostorder(allocator);

    const solution = try regalloc.runRegalloc(@import("BacktrackingAllocator.zig"), allocator, &cfg, abi, &func);

    var consumer = regalloc.SolutionConsumer.init(allocator, solution);
    defer consumer.deinit();

    try target.emit(allocator, &func, &consumer, abi, &object);
    std.debug.print("{s}\n", .{buffer.items});
}
