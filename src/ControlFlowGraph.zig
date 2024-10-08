const std = @import("std");
const ir = @import("ir.zig");

const Index = ir.Index;
const Function = ir.Function;
const Signature = ir.Signature;
const HashSet = @import("hashset.zig").HashSet;

const ControlFlowGraph = @This();

pub const CFGNode = struct {
    preds: HashSet(Index) = .{},
    succs: HashSet(Index) = .{},
};

const Visited = enum {
    None,
    Once,
};

const StackEntry = struct {
    block_ref: Index,
    visited: Visited,
};

entry_ref: Index,
nodes: std.AutoHashMapUnmanaged(Index, CFGNode) = .{},
rpo: std.ArrayListUnmanaged(Index) = .{},

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

    try cfg.computePostorder(allocator);

    return cfg;
}

pub fn computePostorder(self: *ControlFlowGraph, allocator: std.mem.Allocator) !void {
    // we shouldn't visit blocks more than twice (loops)
    var visited_blocks = std.AutoHashMap(Index, void).init(allocator);
    defer visited_blocks.deinit();

    var postorder = std.ArrayList(Index).init(allocator);
    defer postorder.deinit();

    var stack = std.ArrayList(StackEntry).init(allocator);
    defer stack.deinit();

    try stack.append(.{ .block_ref = self.entry_ref, .visited = .None });

    // we visit twice: the first, to add the children; and the second, to add the node itself
    while (stack.items.len != 0) {
        const curr_entry = stack.pop();

        if (curr_entry.visited == .Once) {
            try postorder.append(curr_entry.block_ref);
            continue;
        }

        const cfg_node = self.get(curr_entry.block_ref) orelse @panic("CFG inserted non-existent successors");

        if (visited_blocks.contains(curr_entry.block_ref)) {
            continue;
        }

        try visited_blocks.put(curr_entry.block_ref, void{});

        // mark the block as visited for the second pass
        try stack.append(.{ .block_ref = curr_entry.block_ref, .visited = .Once });

        for (cfg_node.succs.iter()) |succ| {
            try stack.append(.{ .block_ref = succ, .visited = .None });
        }
    }

    while (postorder.popOrNull()) |block_id| {
        try self.rpo.append(allocator, block_id);
    }
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
    self.rpo.deinit(allocator);
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

pub fn getPreds(self: ControlFlowGraph, block_ref: Index) ?HashSet(Index) {
    const node = self.nodes.getPtr(block_ref) orelse return null;
    return node.preds;
}

pub fn getSuccs(self: ControlFlowGraph, block_ref: Index) ?HashSet(Index) {
    const node = self.nodes.getPtr(block_ref) orelse return null;
    return node.succs;
}

pub fn postorderIter(self: *const ControlFlowGraph) std.mem.ReverseIterator(Index) {
    return std.mem.reverseIterator(self.rpo.items);
}

const types = @import("types.zig");
const Instruction = @import("instructions.zig").Instruction;

test "ControlFlowGraph" {
    const allocator = std.testing.allocator;

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
