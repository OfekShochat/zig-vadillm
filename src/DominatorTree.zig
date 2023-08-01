const std = @import("std");
const mem = std.mem;

const ControlFlowGraph = @import("main.zig").ControlFlowGraph;
const Function = @import("main.zig").Function;
const BlockRef = @import("main.zig").BlockRef;
const ValueRef = @import("main.zig").ValueRef;

const DominatorTree = @This();

const ENTRY_REF: BlockRef = 0;

fn HashSet(comptime T: type) type {
    return std.AutoArrayHashMapUnmanaged(T, void);
}

postorder: std.ArrayListUnmanaged(BlockRef) = .{},
nodes: std.AutoHashMapUnmanaged(BlockRef, DomNode) = .{},

pub const DomNode = struct {
    // optional immediate dominator
    idom: ?BlockRef,

    // cache reverse postorder number for dominance computation
    rpo_order: u32,
};

const Visited = enum {
    None,
    Once,
};

const StackEntry = struct {
    block_ref: BlockRef,
    visited: Visited,
};

fn findInitialIdom(self: *DominatorTree, preds: HashSet(BlockRef), entry_ref: BlockRef) ?BlockRef {
    var iter = preds.iterator();
    while (iter.next()) |kv| {
        const pred_ref = kv.key_ptr.*;
        if (self.nodes.get(pred_ref).idom || pred_ref == entry_ref) {
            return pred_ref;
        }
    }

    return null;
}

// FIXME: no pub
pub fn computePostorder(self: *DominatorTree, allocator: mem.Allocator, cfg: *const ControlFlowGraph, func: *const Function) !void {
    // we shouldn't visit blocks more than twice (loops)
    var visited_blocks = std.AutoHashMap(ValueRef, void).init(allocator);
    defer visited_blocks.deinit();

    var stack = std.ArrayList(StackEntry).init(allocator);
    defer stack.deinit();

    try stack.append(.{ .block_ref = func.entryBlock(), .visited = .None });

    // we visit twice: the first, to add the children; and the second, to add the node itself
    while (stack.items.len != 0) {
        const curr_entry = stack.pop();

        if (curr_entry.visited == .Once) {
            try self.postorder.append(allocator, curr_entry.block_ref);
            continue;
        }

        const cfg_node = cfg.get(curr_entry.block_ref).?;

        if (visited_blocks.contains(curr_entry.block_ref)) {
            continue;
        }

        try visited_blocks.put(curr_entry.block_ref, void{});

        // mark the block as visited for the second pass
        try stack.append(.{ .block_ref = curr_entry.block_ref, .visited = .Once });

        for (cfg_node.succs.items) |succ| {
            try stack.append(.{ .block_ref = succ, .visited = .None });
        }
    }
}

fn computeInitialState(self: DominatorTree, allocator: mem.Allocator, cfg: *const ControlFlowGraph, entry_ref: ValueRef) !void {
    try self.nodes.put(allocator, entry_ref, .{ .idom = null, .rpo_order = 0 });

    var rpo_order: u32 = 1;

    var idx = self.postorder.items.len - 1;
    while (idx > 0) : (idx -= 1) {
        const block_ref = self.postorder.items[idx];
        if (block_ref == entry_ref) {
            continue;
        }

        const preds = &cfg.get(block_ref).preds;

        const initial_idom = self.findinitialidom(preds, entry_ref);
        try self.nodes.put(block_ref, .{ .idom = initial_idom, .rpo_order = rpo_order });

        rpo_order += 1;
    }
}

pub fn reversePostorderIter(self: *const DominatorTree) RPOIterator {
    return RPOIterator{
        .idx = self.postorder.items.len - 1,
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

    pub fn next(self: *RPOIterator) ?BlockRef {
        if (self.idx <= 0) {
            return null;
        }

        defer self.idx -= 1;
        return self.domtree.postorder.items[self.idx];
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
        try writer.writeAll("digraph DominatorGraph {{\n");
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

            if (self.dominator_tree.nodes.get(block_ref)) |idom| {
                try writer.print("  {} -> {};\n", .{ idom, block_ref });
            }
        }

        try writer.writeAll("}");
    }
};
