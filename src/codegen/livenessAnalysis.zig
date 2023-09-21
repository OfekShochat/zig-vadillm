const std = @import("std");
const BlockRef = @import("main.zig").BlockRef;
const ControlFlowGraph = @import("../ControlFlowGraph.zig").ControlFlowGraph;
const Block = @import("main.zig").Block;
const Index = @import("../ir.zig").Index;
const MachineFunction = @import("MachineFunction.zig").Function;

pub const LivenessAnalysis = struct {
    cfg: ControlFlowGraph = .{},
    liveness: std.AutoHashMap(Index, std.ArrayList([2]u32)) = .{},

    pub fn getLiveIn(blockRef : BlockRef) std.ArrayList {
        var block = .cfg.nodes[blockRef];
        var live_vars = std.ArrayList(Index);

        for (block.insts) | inst | {
            for(inst.getAllocatableOperands()) |operand| {
                live_vars.append(operand);
            }
        }
        return live_vars;
    }

    pub fn getLiveOut(blockRef : BlockRef) std.ArrayList{
        var block = .cfg.nodes[blockRef];
        var inst = block.getTerminator();
        var live_vars = std.ArrayList(Index);

        switch(inst) {
            inst.jump => |inst_jump| {
                var live_in = getLiveIn(inst_jump.block);
                live_vars.append(live_in);
            },

            inst.brif => |inst_brif| {
                var live_in = getLiveIn(inst_brif.cond_true.block);
                live_in.append(getLiveIn(inst_brif.cond_false.block));
                live_vars.append(live_in);
            },

            //inst.call => |inst_call| {

            //}
        }

        return live_vars;
    }

    pub fn livenessAnalyse() void {
        var iter = .cfg.reversePostorderIter();
        while(iter.next()) |block_ref|{
            var live_out = getLiveOut(block_ref);
            for (live_out) |live_var| {
                try .liveness.put(live_var, block_ref);
            }
        }
    }
};

test "LivenessAnalysis" {
    const types = @import("types.zig");
    const Instruction = @import("main.zig").Instruction;
    var allocator = std.testing.allocator;

    var func = MachineFunction.init(allocator, "add", Signature{
        .ret = types.I32,
        .args = .{},
    });
    defer func.deinit(allocator);

    try func.appendParam(allocator, types.I32);

    const block1 = try func.appendBlock(allocator);
    const block2 = try func.appendBlock(allocator);
    const param1 = try func.appendBlockParam(allocator, block1, types.I32);

    _ = try func.appendInst(
        allocator,
        block1,
        Instruction{ .jump = .{ .block = block2, .args = .{} } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block2,
        Instruction{ .ret = param1 },
        types.I32,
    );

    var cfg = try ControlFlowGraph.fromFunction(allocator, &func);
    defer cfg.deinit(allocator);

    const node1 = cfg.get(block1).?;
    try std.testing.expectEqual(@as(usize, 0), node1.preds.inner.entries.len);
    try std.testing.expectEqual(@as(usize, 1), node1.succs.inner.entries.len);
    try std.testing.expect(node1.succs.contains(block2));

    const node2 = cfg.get(block2).?;
    try std.testing.expectEqual(@as(usize, 1), node2.preds.inner.entries.len);
    try std.testing.expectEqual(@as(usize, 0), node2.succs.inner.entries.len);
    try std.testing.expect(node2.preds.contains(block1));

    var domtree = LivenessAnalysis{};
    //defer domtree.deinit(allocator);

    try domtree.livenessAnalyse(allocator, &cfg, &func);

    //try std.testing.expect(domtree.dominates(block1, block2));
    //try std.testing.expect(!domtree.dominates(block2, block1));
}