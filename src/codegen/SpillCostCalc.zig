const std = @import("std");
const LiveBundle = @import("LinearScanAllocator.zig").LiveBundle;
const VirtualReg = @import("regalloc.zig").VirtualReg;
const Operand = @import("regalloc.zig").Operand;
const MachineFunction = @import("MachineFunction.zig");
const LoopAnalysis = @import("../LoopAnalysis.zig");

const Self = @This();

const use_freq_bonus_per = 100;
const loop_level_bonus = 10;
const block_param_bonus = 50; // looks like an induction variable
const zero_length_cutoff = 3;

const CostBreakdown = struct {
    use_freq: usize,
    bonus: usize,
};

costs: std.AutoHashMap(VirtualReg, usize),

pub fn run(
    self: *Self,
    allocator: std.mem.Allocator,
    func: MachineFunction,
    loop_analysis: LoopAnalysis,
    live_bundles: []LiveBundle,
) !void {
    var block_iter = func.blockIter();
    while (block_iter.next()) |block| {
        var bonus: usize = 0;

        if (loop_analysis.block_map.get(block.id)) |loop_ref| {
            const loop = loop_analysis.loops.get(loop_ref) orelse @panic("Loop Analysis is invalid.");
            bonus += loop.level * loop_level_bonus;
        }

        var operands = std.ArrayList(Operand).init(allocator);

        for (block.insts) |inst| {
            try inst.getAllocatableOperands(&operands);

            for (operands.items) |operand| {
                var cost_breakdown = try self.costs.getOrPutValue(
                    operand.vregIndex(),
                    CostBreakdown{ .bonus = bonus, .use_freq = use_freq_bonus_per },
                );

                cost_breakdown.value_ptr.use_freq += use_freq_bonus_per;
            }
        }

        for (block.params) |param| {
            var cost_breakdown = try self.costs.getOrPutValue(
                param.index,
                CostBreakdown{ .bonus = bonus + block_param_bonus, .use_freq = use_freq_bonus_per },
            );

            cost_breakdown.value_ptr.bonus += block_param_bonus;
        }
    }

    for (live_bundles) |bundle| {
        for (bundle.ranges) |*const_live_range| {
            var live_range = @constCast(const_live_range); // HACK

            if (self.costs.get(live_range.vreg.index)) |cost_breakdown| {
                if (live_range.end - live_range.start < zero_length_cutoff) {
                    live_range.spill_cost = cost_breakdown.bonus + cost_breakdown.use_freq;
                } else {
                    live_range.spill_cost = cost_breakdown.bonus + cost_breakdown.use_freq / (live_range.end - live_range.start);
                }
            }
        }
    }
}
