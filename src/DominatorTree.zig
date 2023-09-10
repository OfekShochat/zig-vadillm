const std = @import("std");

const ControlFlowGraph = @import("ControlFlowGraph.zig");
const Signature = @import("function.zig").Signature;
const Module = @import("Module.zig");
const Index = @import("ir.zig").Index;
const Function = @import("function.zig").Function;
const HashSet = @import("hashset.zig").HashSet;

const DominatorTree = @This();

postorder: std.ArrayListUnmanaged(Index) = .{},
nodes: std.AutoHashMapUnmanaged(Index, DomNode) = .{},

pub const DomNode = struct {
    // optional immediate dominator
    idom: ?Index,

    // cache reverse postorder number for dominance computation
    rpo_order: u32,
};

const Visited = enum {
    None,
    Once,
};

const StackEntry = struct {
    block_ref: Index,
    visited: Visited,
};

pub fn deinit(self: *DominatorTree, allocator: std.mem.Allocator) void {
    self.postorder.deinit(allocator);
    self.nodes.deinit(allocator);
}

pub fn preallocate(self: *DominatorTree, allocator: std.mem.Allocator, blocks: usize) !void {
    try self.nodes.ensureTotalCapacity(allocator, @intCast(blocks));
}

pub fn compute(self: *DominatorTree, allocator: std.mem.Allocator, cfg: *const ControlFlowGraph) !void {
    if (cfg.nodes.size == 0) {
        // nothing to do, there's only one (or less) live block(s)
        return;
    }

    try self.computePostorder(allocator, cfg);
    try self.computeDomtree(allocator, cfg);
}

fn computePostorder(self: *DominatorTree, allocator: std.mem.Allocator, cfg: *const ControlFlowGraph) !void {
    // we shouldn't visit blocks more than twice (loops)
    var visited_blocks = std.AutoHashMap(Index, void).init(allocator);
    defer visited_blocks.deinit();

    var stack = std.ArrayList(StackEntry).init(allocator);
    defer stack.deinit();

    try stack.append(.{ .block_ref = cfg.entry_ref, .visited = .None });

    // we visit twice: the first, to add the children; and the second, to add the node itself
    while (stack.items.len != 0) {
        const curr_entry = stack.pop();

        if (curr_entry.visited == .Once) {
            try self.postorder.append(allocator, curr_entry.block_ref);
            continue;
        }

        const cfg_node = cfg.get(curr_entry.block_ref) orelse @panic("CFG inserted non-existent successors");

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
}

pub fn dominates(self: DominatorTree, a: Index, b: Index) bool {
    // blocks that aren't in the domtree cannot be checked for dominance
    if (!self.nodes.contains(a) or !self.nodes.contains(b)) {
        return false;
    }

    const order_a = self.nodes.getPtr(a).?.rpo_order;
    var finger = b;

    // as long as the rpo order is greater to a's, we're below it
    while (self.nodes.get(finger).?.rpo_order > order_a) {
        const idom = self.nodes.getPtr(finger).?.idom orelse return false;
        finger = idom;
    }

    return finger == a;
}

fn findInitialIdom(self: *DominatorTree, preds: *const HashSet(Index), entry_ref: Index) ?Index {
    for (preds.iter()) |pred_ref| {
        var pred = self.nodes.getPtr(pred_ref) orelse @panic("rpo ensures that all parents are visited before the child");
        if (pred.idom != null or pred_ref == entry_ref) {
            return pred_ref;
        }
    }

    return null;
}

fn updateDominators(self: *DominatorTree, current_block: Index, cfg: *const ControlFlowGraph) struct { val: Index, changed: bool } {
    var new_idom = self.nodes.get(current_block).?.idom orelse @panic("rpo ensures that at least one parent is visited before a child");

    var preds = &cfg.get(current_block).?.preds;
    for (preds.iter()) |pred| {
        std.debug.assert(self.nodes.contains(pred));

        // if pred is different and reachable (entry block would've been found before),
        // set the common acenstor as the dominator
        if (pred != new_idom and self.nodes.getPtr(pred).?.idom != null) {
            new_idom = self.commonDominatingAncestor(pred, new_idom);
        }
    }

    return .{
        .val = new_idom,
        .changed = self.nodes.getPtr(current_block).?.idom != new_idom,
    };
}

fn computeDomtree(self: *DominatorTree, allocator: std.mem.Allocator, cfg: *const ControlFlowGraph) !void {
    try self.computeInitialState(allocator, cfg, cfg.entry_ref);

    // unless the cfg has an an irreducible control flow, such as a loop with two entry points,
    // this should exit after one iteration
    var changed = true;
    while (changed) {
        changed = false;

        var iter = self.reversePostorderIter();
        while (iter.next()) |block_ref| {
            if (block_ref == cfg.entry_ref) {
                continue;
            }

            const new_idom = self.updateDominators(block_ref, cfg);

            if (new_idom.changed) {
                self.nodes.getPtr(block_ref).?.idom = new_idom.val;
                changed = true;
            }
        }
    }
}

fn computeInitialState(self: *DominatorTree, allocator: std.mem.Allocator, cfg: *const ControlFlowGraph, entry_ref: Index) !void {
    try self.nodes.put(allocator, entry_ref, .{ .idom = null, .rpo_order = 0 });

    var rpo_order: u32 = 1;

    var iter = self.reversePostorderIter();
    while (iter.next()) |block_ref| {
        if (block_ref == entry_ref) {
            continue;
        }

        const preds = &cfg.get(block_ref).?.preds;

        const initial_idom = self.findInitialIdom(preds, entry_ref) orelse @panic("there should always be an initial idom");
        try self.nodes.put(allocator, block_ref, .{ .idom = initial_idom, .rpo_order = rpo_order });

        rpo_order += 1;
    }
}

/// finds intersection point of dominators
fn commonDominatingAncestor(self: DominatorTree, block1: Index, block2: Index) Index {
    std.debug.assert(self.nodes.contains(block1) and self.nodes.contains(block2));

    var finger1 = block1;
    var finger2 = block2;

    while (true) {
        const node1 = self.nodes.get(finger1).?;
        const node2 = self.nodes.get(finger2).?;

        if (node1.rpo_order < node2.rpo_order) {
            // node1 comes before node2 (in rpo), move finger2 (node2) up
            finger2 = node2.idom orelse @panic("reachable block that is unreachable?");
        } else if (node1.rpo_order > node2.rpo_order) {
            // node2 comes before node1 (in rpo), move finger1 (node1) up
            finger1 = node1.idom orelse @panic("reachable block that is unreachable?");
        } else {
            break;
        }
    }

    return finger1;
}

pub fn reversePostorderIter(self: *const DominatorTree) RPOIterator {
    return RPOIterator{
        .idx = self.postorder.items.len,
        .domtree = self,
    };
}

pub fn formatter(self: *const DominatorTree, func: *const Function) DominatorTreeFormatter {
    return DominatorTreeFormatter{
        .func = func,
        .dominator_tree = self,
    };
}

pub const RPOIterator = struct {
    idx: usize,
    domtree: *const DominatorTree,

    pub fn next(self: *RPOIterator) ?Index {
        if (self.idx > 0) {
            self.idx -= 1;
            return self.domtree.postorder.items[self.idx];
        }

        return null;
    }
};

pub const DominatorTreeFormatter = struct {
    func: *const Function,
    dominator_tree: *const DominatorTree,

    pub fn format(
        self: DominatorTreeFormatter,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("digraph DominatorGraph {\n");
        try writer.writeAll("  // node attributes\n");
        try writer.writeAll("  // graph attributes\n");

        for (self.dominator_tree.postorder.items) |block_ref| {
            try writer.print("  {} [label=\"{}\"];\n", .{ block_ref, block_ref });
        }

        try writer.writeAll("  // edge attributes\n");

        var iter = self.dominator_tree.reversePostorderIter();
        while (iter.next()) |block_ref| {
            if (block_ref == self.func.entryBlock()) {
                continue;
            }

            if (self.dominator_tree.nodes.getPtr(block_ref)) |domnode| {
                try writer.print("  {} -> {};\n", .{ domnode.idom.?, block_ref });
            }
        }

        try writer.writeAll("}");
    }
};

const types = @import("types.zig");
const Instruction = @import("instructions.zig").Instruction;

test "DominatorTree.simple" {
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

    var domtree = DominatorTree{};
    defer domtree.deinit(allocator);

    try domtree.compute(allocator, &cfg);

    try std.testing.expect(domtree.dominates(block1, block2));
    try std.testing.expect(!domtree.dominates(block2, block1));
}

test "DominatorTree.loops" {
    var allocator = std.testing.allocator;

    var func = Function.init(allocator, Signature{
        .ret = types.I32,
        .args = .{},
    });
    defer func.deinit(allocator);

    try func.appendParam(allocator, types.I32);

    const block1 = try func.appendBlock(allocator);
    const block2 = try func.appendBlock(allocator);
    const block3 = try func.appendBlock(allocator);
    const block4 = try func.appendBlock(allocator);
    const param1 = try func.appendBlockParam(allocator, block1, types.I32);

    const const1 = try func.addConst(allocator, &std.mem.toBytes(10), types.I32);

    var args = std.ArrayListUnmanaged(Index){};
    try args.append(allocator, const1);
    defer args.deinit(allocator);
    _ = try func.appendInst(
        allocator,
        block1,
        Instruction{ .jump = .{ .block = block2, .args = args } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block2,
        Instruction{ .jump = .{ .block = block3, .args = args } },
        types.I32,
    );

    const cond = try func.appendInst(
        allocator,
        block3,
        Instruction{ .icmp = .{ .cond_code = .UnsignedLessThan, .lhs = param1, .rhs = const1 } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block3,
        Instruction{ .brif = .{
            .cond = cond,
            .cond_true = .{ .block = block2, .args = .{} },
            .cond_false = .{ .block = block4, .args = .{} },
        } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block4,
        Instruction{ .ret = null },
        types.I32,
    );

    var cfg = try ControlFlowGraph.fromFunction(allocator, &func);
    defer cfg.deinit(allocator);

    var domtree = DominatorTree{};
    defer domtree.deinit(allocator);

    try domtree.compute(allocator, &cfg);

    try std.testing.expect(domtree.dominates(block1, block1));
    try std.testing.expect(domtree.dominates(block2, block2));
    try std.testing.expect(domtree.dominates(block3, block3));

    try std.testing.expect(domtree.dominates(block1, block2));
    try std.testing.expect(domtree.dominates(block1, block3));

    try std.testing.expect(domtree.dominates(block2, block3));

    try std.testing.expect(!domtree.dominates(block3, block1));
    try std.testing.expect(!domtree.dominates(block3, block2)); // backedges aren't considered dominating
}
