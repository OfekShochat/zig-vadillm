//! This computes the live ranges of non-static (everything that isn't a constant) values.

const std = @import("std");

const regalloc = @import("regalloc.zig");
const codegen = @import("../codegen.zig");

const MachineInst = @import("MachineInst.zig");
const MachineFunction = @import("MachineFunction.zig");
const DominatorTree = @import("../DominatorTree.zig");
const ControlFlowGraph = @import("../ControlFlowGraph.zig");
const CodePoint = @import("CodePoint.zig");
const Abi = @import("Abi.zig");
const LoopAnalysis = @import("../LoopAnalysis.zig");

const Liveness = @This();

// map from a block to all the live-in values in the block
liveins: std.AutoHashMap(codegen.Index, std.DynamicBitSetUnmanaged),

// map from a block to all the live-out values in the block
liveouts: std.AutoHashMap(codegen.Index, std.DynamicBitSetUnmanaged),

arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator) Liveness {
    return Liveness{
        .liveins = std.AutoHashMap(codegen.Index, std.DynamicBitSetUnmanaged).init(allocator),
        .liveouts = std.AutoHashMap(codegen.Index, std.DynamicBitSetUnmanaged).init(allocator),
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn deinit(self: *Liveness, allocator: std.mem.Allocator) void {
    var iter = self.liveins.valueIterator();
    while (iter.next()) |v| {
        v.deinit(allocator);
    }
    self.liveins.deinit();
    iter = self.liveouts.valueIterator();
    while (iter.next()) |v| {
        v.deinit(allocator);
    }
    self.liveouts.deinit();
}

pub fn compute(
    self: *Liveness,
    allocator: std.mem.Allocator,
    cfg: *const ControlFlowGraph,
    abi: Abi,
    func: *const MachineFunction,
) ![]const *regalloc.LiveRange {
    try self.computeLiveSets(allocator, abi, cfg, func);
    return self.computeLiveRanges(self.arena.allocator(), abi, func);
}

fn upAndMark(
    self: *Liveness,
    allocator: std.mem.Allocator,
    func: *const MachineFunction,
    abi: Abi,
    cfg: *const ControlFlowGraph,
    block_ref: codegen.Index,
    v: codegen.Index,
) !void {
    var operands = std.ArrayList(regalloc.Operand).init(allocator);
    defer operands.deinit();

    const block = func.getBlock(block_ref).?;

    // 2: if def(v) ∈ B (φ excluded) then return # Killed in the block, stop
    for (block.insts) |inst| {
        try inst.getAllocatableOperands(abi, &operands);
        for (operands.items) |operand| {
            if (operand.accessType() == .def and operand.vregIndex() == v) return;
        }
        operands.clearRetainingCapacity();
    }

    // 3: if v ∈ LiveIn(B) then return # propagation already done, stop
    var liveins = self.liveins.getPtr(block_ref).?;
    if (liveins.isSet(v)) {
        return;
    }

    // 4: LiveIn(B) = LiveIn(B) ∪ {v}
    liveins.set(v);

    // 5: if v ∈ PhiDefs(B) then return # Do not propagate φ definitions
    // for (block.params) |param| {
    //     if (param.index == v) {
    //         return;
    //     }
    // }

    // 6: for each P ∈ CFG_preds(B) do # Propagate backward
    for (cfg.getPreds(block_ref).?.iter()) |pred_ref| {
        // 7: LiveOut(P) = LiveOut(P ) ∪ {v}
        // 8: Up_and_Mark(B, v)
        self.liveouts.getPtr(pred_ref).?.set(v);
        try self.upAndMark(allocator, func, abi, cfg, block_ref, v);
    }
}

fn computeLiveSets(
    self: *Liveness,
    allocator: std.mem.Allocator,
    abi: Abi,
    cfg: *const ControlFlowGraph,
    func: *const MachineFunction,
) !void {
    // for all blocks, add their liveins and liveouts, with <number of vregs used> bits.

    // 2: for each basic block B in CFG do # Consider all blocks successively
    for (cfg.rpo.items) |block_ref| {
        const block = func.getBlock(block_ref).?;

        // // 3: for each v ∈ PhiUses(B) do # Used in the φ of a successor block
        // for (block.succ_phis) |block_call| {
        //     // 3: for each v ∈ PhiUses(B) do # Used in the φ of a successor block
        //     for (block_call.operands) |operand| {
        //         // 4: LiveOut(B) = LiveOut(B) ∪ {v}
        //         // 5: Up_and_Mark(B, v)
        //         self.liveouts.getPtr(block_ref).?.set(operand);
        //         self.upAndMark(func, block_ref, operand);
        //     }
        // }

        try self.liveins.put(block.id, try std.DynamicBitSetUnmanaged.initEmpty(
            allocator,
            func.num_virtual_regs,
        ));

        try self.liveouts.put(block.id, try std.DynamicBitSetUnmanaged.initEmpty(
            allocator,
            func.num_virtual_regs,
        ));

        var operands = std.ArrayList(regalloc.Operand).init(allocator);
        defer operands.deinit();

        for (block.insts) |inst| {
            try inst.getAllocatableOperands(abi, &operands);

            // 6: for each v used in B (φ excluded) do # Traverse B to find all uses
            for (operands.items) |operand| {
                if (operand.accessType() == .use) {
                    // 7: Up_and_Mark(B, v)
                    try self.upAndMark(allocator, func, abi, cfg, block_ref, operand.vregIndex());
                }
            }
            operands.clearRetainingCapacity();
        }
    }
}

const LiveRangeBuilder = struct {
    uses: std.ArrayList(CodePoint),
    start: CodePoint = CodePoint.invalidMax(),
    end: CodePoint = CodePoint.invalidMax(),
    vreg: regalloc.VirtualReg,
    constraint: regalloc.LocationConstraint,
};

fn computeLiveRanges(
    self: *Liveness,
    allocator: std.mem.Allocator,
    abi: Abi,
    func: *const MachineFunction,
) ![]const *regalloc.LiveRange {
    var operands_temp = std.ArrayList(regalloc.Operand).init(allocator);
    defer operands_temp.deinit();

    var live_ranges = std.ArrayList(*regalloc.LiveRange).init(allocator);

    var blocks_iter = func.reverseBlockIter();
    while (blocks_iter.next()) |block| {
        var current = block.end.getNextInst();

        const liveout = self.liveouts.get(block.id).?;

        var ranges_in_flight = std.AutoArrayHashMap(codegen.Index, LiveRangeBuilder).init(allocator);
        defer ranges_in_flight.deinit();

        var insts_iter = std.mem.reverseIterator(block.insts);
        while (insts_iter.next()) |inst| {
            current = current.getPrevInst();

            try inst.getAllocatableOperands(abi, &operands_temp);

            for (operands_temp.items) |operand| {
                const entry = try ranges_in_flight.getOrPutValue(
                    operand.vregIndex(),
                    LiveRangeBuilder{
                        .uses = std.ArrayList(CodePoint).init(allocator),
                        .vreg = operand.vreg(),
                        .constraint = operand.locationConstraints(),
                    },
                );

                if (!entry.found_existing) {
                    entry.value_ptr.end = current;
                    entry.value_ptr.start = block.start;
                }

                if (operand.accessType() == .use) {
                    try entry.value_ptr.uses.append(current);
                } else {
                    entry.value_ptr.start = current;
                }

                if (operand.locationConstraints() == .reuse) {
                    // somehow add it to the same interval.
                }

                if (liveout.isSet(operand.vregIndex())) {
                    entry.value_ptr.end = block.end;
                }
            }

            operands_temp.clearRetainingCapacity();
        }

        for (ranges_in_flight.values()) |*builder| {
            const ranges = try allocator.alloc(*regalloc.LiveRange, 1);
            const interval = try allocator.create(regalloc.LiveInterval);
            interval.* = .{
                .allocation = null,
                .ranges = ranges,
                .constraints = builder.constraint,
            };

            const range = try allocator.create(regalloc.LiveRange);
            range.* = regalloc.LiveRange{
                .vreg = builder.vreg,
                .start = builder.start,
                .end = builder.end,
                .uses = try builder.uses.toOwnedSlice(),
                .live_interval = interval,
            };

            ranges[0] = range;

            try live_ranges.append(range);
        }
    }

    return live_ranges.toOwnedSlice();
    // TODO: coalescing pass for phi stuff: forward, if you find a copy to a vreg from a vreg (should this be marked as a phi thing?), log it and try to find the blocks that use it. If it finds the live range, coalesce it into the same interval.
}

test "Liveness" {
    // try liveness.compute(allocator, undefined, &cfg, &func);
}
