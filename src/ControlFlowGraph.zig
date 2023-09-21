const std = @import("std");
const ir = @import("ir.zig");
const MachineFunction = @import("codegen/MachineFunction.zig");

const Index = ir.Index;
const Function = ir.Function;
const Signature = ir.Signature;
const HashSet = @import("hashset.zig").HashSet;

const ControlFlowGraph = @This();

pub const CFGNode = struct {
    preds: HashSet(Index) = .{},
    succs: HashSet(Index) = .{},
};

entry_ref: Index,
nodes: std.AutoHashMapUnmanaged(Index, CFGNode) = .{},

pub fn fromFunction(allocator: std.mem.Allocator, func: *const Function) !ControlFlowGraph {
    var cfg = ControlFlowGraph{ .entry_ref = func.entryBlock() };

    var iter = func.blocks.iterator();
    while (iter.next()) |kv| {
        switch (kv.value_ptr.getTerminator()) {
            .brif => |brif| {
                try cfg.addEdge(allocator, kv.key_ptr.*, brif.cond_true.block);
                try cfg.addEdge(allocator, kv.key_ptr.*, brif.cond_false.block);
            },
            .jump => |jump| try cfg.addEdge(allocator, kv.key_ptr.*, jump.block),
            else => {},
        }
    }

    return cfg;
}

pub fn fromMachineFunction(allocator: std.mem.Allocator, func: *const MachineFunction) !ControlFlowGraph{
    var cfg = ControlFlowGraph{ .entry_ref = 0};

    var iter = func.blocks.iterator();
    while (iter.next()) |block| {
        var terminator = block.getTerminator();
        var branches = terminator.getBranches();
        for (branches) |branch| {
            try cfg.addEdge(allocator, block.getBlockByInst(terminator), branch);
        }
    }

    return cfg;
}

// pub fn fromMachineFunction(allocator: std.mem.Allocator, func: *const MachineFunction) !ControlFlowGraph {
//     var cfg = ControlFlowGraph{};

//     var iter = func.blocks.iterator();
//     while (iter.next()) |kv| {
//         for (getBlockSuccs(kv.value_ptr)) |succ| {
//             cfg.addEdge(allocator, kv.key_ptr.*, succ);
//         }
//     }

//     return cfg;
// }

pub fn deinit(self: *ControlFlowGraph, allocator: std.mem.Allocator) void {
    var iter = self.nodes.valueIterator();
    while (iter.next()) |node| {
        node.preds.deinit(allocator);
        node.succs.deinit(allocator);
    }
    self.nodes.deinit(allocator);
}

fn addEdge(self: *ControlFlowGraph, allocator: std.mem.Allocator, from: Index, to: Index) !void {
    std.log.debug("cfg edge: {} {}", .{ from, to });

    var cfg_entry = try self.nodes.getOrPutValue(allocator, from, CFGNode{});
    try cfg_entry.value_ptr.succs.put(allocator, to);

    cfg_entry = try self.nodes.getOrPutValue(allocator, to, CFGNode{});
    try cfg_entry.value_ptr.preds.put(allocator, from);
}

pub fn get(self: ControlFlowGraph, block_ref: Index) ?*const CFGNode {
    return self.nodes.getPtr(block_ref);
}

const types = @import("types.zig");
const Instruction = @import("instructions.zig").Instruction;

test "ControlFlowGraph" {
    var allocator = std.testing.allocator;

    var func = Function.init(allocator, Signature{
        .ret = types.I32,
        .args = .{},
    });
    defer func.deinit(allocator);

    try func.appendParam(allocator, types.I32);

    const block1 = try func.appendBlock(allocator);
    const block2 = try func.appendBlock(allocator);
    const param1 = try func.appendBlockParam(allocator, block1, types.I32);

    // var block1_args = try allocator.alloc(Index, 0);

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
}
