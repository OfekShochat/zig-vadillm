const std = @import("std");
const ControlFlowGraph = @import("../ControlFlowGraph.zig").ControlFlowGraph;
const Block = @import("main.zig").Block;
const Index = @import("../ir.zig").Index;
const MachineFunction = @import("MachineFunction.zig").Function;
const mem = @import("mem.zig");

pub const LivenessNode = struct {
    start_of_liverange: Index,
    end_of_liverange: Index,
    index: Index,
};

pub const LiveInBlock = struct {
    index: Index,
    pred: Index,
    succs: std.ArrayList(Index),
};

pub const LivenessAnalysis = struct {
    cfg: ControlFlowGraph = .{},
    liveness: std.AutoHashMap(Index, std.ArrayList(LivenessNode)) = .{},
    live_ranges: std.AutoHashMap(Index, std.ArrayList(u32[2])) = .{},
    number_of_live_ranges: u32 = 0,

    pub fn getLiveIn(self: *LivenessAnalysis, blockRef : Index) std.ArrayList {
        var block = self.cfg.nodes[blockRef];
        var live_vars = std.ArrayList(Index);

        for (block.insts) | inst | {
            for(inst.getAllocatableOperands()) |operand| {
                live_vars.append(operand);
            }
        }

        return live_vars;
    }

    pub fn getLiveOut(self: *LivenessAnalysis, blockRef : Index) std.ArrayList{
        var block = self.cfg.nodes[blockRef];
        var inst = block.getTerminator();
        var live_vars = std.ArrayList(Index);
        var branches = inst.getBranches();

        for(branches) |branch| {
            live_vars.append(getLiveIn(branch));
        }

        return live_vars;
    }

    pub fn computeLiveins(self: *LivenessAnalysis) !void {
        self.cfg.computePostorder();
        for(self.cfg.postorder.items) |block_index| {
            getLiveIn(block_index);
        }
    }

    pub fn livenessAnalyse(self: LivenessAnalysis, vreg: Index) void {
        var live_ranges = self.live_ranges.get(vreg);
        const number_of_live_ranges = self.number_of_live_ranges;

        var vreg_liveness = try self.liveness.get(vreg);
        for(vreg_liveness.items) |liveInterval| {

            live_ranges[number_of_live_ranges][0] = liveInterval;
            live_ranges[number_of_live_ranges][1] = liveInterval;

            var block = self.cfg.nodes[liveInterval];
            var branches = block.getTerminator().getBranches();
            if(branches.items.len > 1) {

                for(branches.items) |branch|{
                    live_ranges.append(live_ranges[number_of_live_ranges]);
                    self.number_of_live_ranges += 1;
                    livenessAnalyse(vreg);
                }

            } else {

                if(check_if_block_in_liveness(vreg, branches.items[0])) {
                    live_ranges[number_of_live_ranges][1] = branches.items[0];
                }

            }
        }

        return;
    }

    pub fn check_if_block_in_liveness(self: LivenessAnalysis, vreg: Index, block: Index) bool {
        var liveness = self.liveness.get(vreg);
        for(liveness) |live_var| {
            if(live_var == block) {
                return true;
            }
        }

        return false;
    }

    pub fn buildRanges(liveInBlock: *std.ArrayList(LiveInBlock)) std.ArrayList(LivenessNode) {
        sort(liveInBlock, 0, liveInBlock.items.len - 1);
        var node = LivenessNode{.pred = liveInBlock.items[0].block, .succs = liveInBlock.items[0].block, .index = liveInBlock.items[0].index};
        var liveness_list = std.ArrayList(LivenessNode);

        for(liveInBlock.items()) |block| {
            var current_node = liveness_list.items.len - 1;

            if (liveness_list.items[current_node].sucss + 1 == block.block) {
                node.succs = block.block;

            } else {
                liveness_list.addOne();
                liveness_list.items[current_node+1] = LivenessNode {.pred = block.block, .succs = block.block, .index = block.index};
            }

        }

        return liveness_list;
    }

    pub fn sort(liveInBlock: *std.ArrayList(LiveInBlock), lo: Index, hi: Index) void {
        if (lo < hi) {
            var p = partition(liveInBlock, lo, hi);
            sort(liveInBlock, lo, @min(p, p -% 1));
            sort(liveInBlock, p + 1, hi);
        }
    }

    pub fn partition(liveInBlock: *std.ArrayList(LiveInBlock), lo: usize, hi: usize) usize {
        var pivot = liveInBlock.items[hi].block;
        var i = lo;
        var j = lo;
        while (j < hi) : (j += 1) {
            if (liveInBlock.items[j].block < pivot) {
                mem.swap(i32, &liveInBlock.items[i], &liveInBlock.items[j]);
                i = i + 1;
            }
        }
        mem.swap(i32, &liveInBlock.items[i], &liveInBlock.items[hi]);
        return i;
    }
};

test "LivenessAnalysis" {
    // const types = @import("types.zig");
    const Instruction = @import("dummy_inst.zig").Instruction;
    var allocator = std.testing.allocator;

    var func = MachineFunction.init(allocator, "add", Signature{
        .ret = types.I32,
        .args = .{},
    });
    defer func.deinit(allocator);

    var basic_block = std.ArrayList(Insts);
    basic_block.append();

    func.addBlock();

    try func.appendParam(allocator, types.I32);

    // const block1 = try func.appendBlock(allocator);
    // const block2 = try func.appendBlock(allocator);
    // const param1 = try func.appendBlockParam(allocator, block1, types.I32);

    // _ = try func.appendInst(
        // allocator,
        // block1,
        // Instruction{ .jump = .{ .block = block2, .args = .{} } },
        // types.I32,
    // );

    // _ = try func.appendInst(
        // allocator,
        // block2,
        // Instruction{ .ret = param1 },
        // types.I32,
    // );

    // var cfg = try ControlFlowGraph.fromFunction(allocator, &func);
    // defer cfg.deinit(allocator);

    // const node1 = cfg.get(block1).?;
    // try std.testing.expectEqual(@as(usize, 0), node1.preds.inner.entries.len);
    // try std.testing.expectEqual(@as(usize, 1), node1.succs.inner.entries.len);
    // try std.testing.expect(node1.succs.contains(block2));

    // const node2 = cfg.get(block2).?;
    // try std.testing.expectEqual(@as(usize, 1), node2.preds.inner.entries.len);
    // try std.testing.expectEqual(@as(usize, 0), node2.succs.inner.entries.len);
    // try std.testing.expect(node2.preds.contains(block1));

    // var domtree = LivenessAnalysis{};
    //defer domtree.deinit(allocator);

    // try domtree.livenessAnalyse(allocator, &cfg, &func);

    //try std.testing.expect(domtree.dominates(block1, block2));
    //try std.testing.expect(!domtree.dominates(block2, block1));
}