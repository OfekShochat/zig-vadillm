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

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Liveness {
    return Liveness{
        .liveins = std.AutoHashMap(codegen.Index, std.DynamicBitSetUnmanaged).init(allocator),
        .liveouts = std.AutoHashMap(codegen.Index, std.DynamicBitSetUnmanaged).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Liveness) void {
    var iter = self.liveins.valueIterator();
    while (iter.next()) |v| {
        v.deinit(self.allocator);
    }
    self.liveins.deinit();
    iter = self.liveouts.valueIterator();
    while (iter.next()) |v| {
        v.deinit(self.allocator);
    }
    self.liveouts.deinit();
}

pub fn compute(
    self: *Liveness,
    cfg: *const ControlFlowGraph,
    abi: Abi,
    func: *const MachineFunction,
) ![]const *regalloc.LiveRange {
    try self.computeLiveSets(abi, cfg, func);
    return self.computeLiveRanges(abi, func);
}

fn upAndMark(
    self: *Liveness,
    func: *const MachineFunction,
    abi: Abi,
    cfg: *const ControlFlowGraph,
    block_ref: codegen.Index,
    v: codegen.Index,
) !void {
    var operands = std.ArrayList(regalloc.Operand).init(self.allocator);
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

    // 6: for each P ∈ CFG_preds(B) do # Propagate backward
    for (cfg.getPreds(block_ref).?.iter()) |pred_ref| {
        // 7: LiveOut(P) = LiveOut(P ) ∪ {v}
        // 8: Up_and_Mark(B, v)
        self.liveouts.getPtr(pred_ref).?.set(v);
        try self.upAndMark(func, abi, cfg, block_ref, v);
    }
}

fn computeLiveSets(
    self: *Liveness,
    abi: Abi,
    cfg: *const ControlFlowGraph,
    func: *const MachineFunction,
) !void {
    // for all blocks, add their liveins and liveouts, with <number of vregs used> bits.

    // 2: for each basic block B in CFG do # Consider all blocks successively
    for (cfg.rpo.items) |block_ref| {
        const block = func.getBlock(block_ref).?;

        try self.liveins.put(block.id, try std.DynamicBitSetUnmanaged.initEmpty(
            self.allocator,
            func.num_virtual_regs,
        ));

        try self.liveouts.put(block.id, try std.DynamicBitSetUnmanaged.initEmpty(
            self.allocator,
            func.num_virtual_regs,
        ));

        var operands = std.ArrayList(regalloc.Operand).init(self.allocator);
        defer operands.deinit();

        for (block.insts) |inst| {
            try inst.getAllocatableOperands(abi, &operands);

            // 6: for each v used in B (φ excluded) do # Traverse B to find all uses
            for (operands.items) |operand| {
                if (operand.accessType() == .use) {
                    // 7: Up_and_Mark(B, v)
                    try self.upAndMark(func, abi, cfg, block_ref, operand.vregIndex());
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

const LiveRangeId = struct { index: u32, constraint: regalloc.LocationConstraint };

fn computeLiveRanges(
    self: *Liveness,
    abi: Abi,
    func: *const MachineFunction,
) ![]const *regalloc.LiveRange {
    var operands_temp = std.ArrayList(regalloc.Operand).init(self.allocator);
    defer operands_temp.deinit();

    var live_ranges = std.ArrayList(*regalloc.LiveRange).init(self.allocator);

    var blocks_iter = func.reverseBlockIter();
    while (blocks_iter.next()) |block| {
        var current = block.end.getNextInst();

        const liveout = self.liveouts.get(block.id).?;

        var ranges_in_flight = std.AutoArrayHashMap(codegen.Index, LiveRangeBuilder).init(self.allocator);
        defer ranges_in_flight.deinit();

        var insts_iter = std.mem.reverseIterator(block.insts);
        while (insts_iter.next()) |inst| {
            current = current.getPrevInst();

            try inst.getAllocatableOperands(abi, &operands_temp);

            for (operands_temp.items) |operand| {
                const constraint = operand.locationConstraints();

                const entry = try ranges_in_flight.getOrPutValue(
                    operand.vregIndex(),
                    LiveRangeBuilder{
                        .uses = std.ArrayList(CodePoint).init(self.allocator),
                        .vreg = operand.vreg(),
                        .constraint = constraint,
                        .start = block.start,
                        .end = if (operand.operandUse() == .early) current else current.getLate(),
                    },
                );

                if (!std.meta.eql(constraint, entry.value_ptr.constraint)) {
                    const builder = entry.value_ptr;
                    const ranges = try self.allocator.alloc(*regalloc.LiveRange, 1);
                    const interval = try self.allocator.create(regalloc.LiveInterval);
                    interval.* = .{
                        .allocation = null,
                        .ranges = ranges,
                        .constraints = builder.constraint,
                    };

                    const range = try self.allocator.create(regalloc.LiveRange);
                    range.* = regalloc.LiveRange{
                        .vreg = builder.vreg,
                        .start = current.getNextInst(),
                        .end = builder.end,
                        .uses = try builder.uses.toOwnedSlice(),
                        .live_interval = interval,
                    };

                    ranges[0] = range;

                    try live_ranges.append(range);

                    entry.value_ptr.* = LiveRangeBuilder{
                        .uses = std.ArrayList(CodePoint).init(self.allocator),
                        .vreg = operand.vreg(),
                        .constraint = constraint,
                        .start = block.start,
                        .end = current.getLate(),
                    };
                }

                if (operand.accessType() == .use) {
                    try entry.value_ptr.uses.append(current);
                } else {
                    entry.value_ptr.start = current;
                }

                if (operand.locationConstraints() == .reuse) {
                    // TODO: somehow add it to the same interval.
                }

                if (liveout.isSet(operand.vregIndex())) {
                    entry.value_ptr.end = block.end;
                }
            }

            operands_temp.clearRetainingCapacity();
        }

        for (ranges_in_flight.values()) |*builder| {
            // put this into a function
            const ranges = try self.allocator.alloc(*regalloc.LiveRange, 1);
            const interval = try self.allocator.create(regalloc.LiveInterval);
            interval.* = .{
                .allocation = null,
                .ranges = ranges,
                .constraints = builder.constraint,
            };

            const range = try self.allocator.create(regalloc.LiveRange);
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

    std.debug.print("{any}\n", .{live_ranges.items});

    return live_ranges.toOwnedSlice();
    // TODO: coalescing pass for phi stuff: forward, if you find a copy to a vreg from a vreg (should this be marked as a phi thing?), log it and try to find the blocks that use it. If it finds the live range, coalesce it into the same interval.
}

test "Liveness" {
    // try liveness.compute(allocator, undefined, &cfg, &func);
}
