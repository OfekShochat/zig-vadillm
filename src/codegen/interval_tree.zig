const std = @import("std");
const builtin = @import("builtin");

/// `T` has to have a `T.start` and an `T.end`.
// This is a Self Balancing Red-Black Tree with a maximum endpoint at each node.
pub fn IntervalTree(comptime T: type) type {
    return struct {
        const DerefedT = switch (@typeInfo(T)) {
            .Pointer => |Ptr| Ptr.child,
            else => T,
        };

        comptime {
            if (!@hasField(DerefedT, "start") or !@hasField(DerefedT, "end")) {
                @compileError("`T` has to have both `T.start` and `T.end`.");
            }
        }

        const Self = @This();

        pub const Color = enum { red, black, white };

        pub fn rangesIntersect(a: T, b: T) bool {
            return (a.rawStart() >= b.rawStart() and a.rawStart() <= b.rawEnd()) or
                (b.rawStart() >= a.rawStart() and b.rawStart() <= a.rawEnd());
        }

        const Node = struct {
            range: T,
            color: Color,
            max_end: usize,
            parent: *Node = undefined,
            right: *Node = undefined,
            left: *Node = undefined,
        };

        var sentinel = Node{
            .range = undefined,
            .color = .black,
            .max_end = undefined,
        };

        arena: std.heap.ArenaAllocator,
        root: *Node,

        pub fn init(allocator: std.mem.Allocator) Self {
            sentinel.left = &sentinel;
            sentinel.right = &sentinel;
            sentinel.parent = &sentinel;

            return Self{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .root = &sentinel,
            };
        }

        pub fn initWithArena(arena: std.heap.ArenaAllocator) Self {
            sentinel.left = &sentinel;
            sentinel.right = &sentinel;
            sentinel.parent = &sentinel;

            return Self{
                .arena = arena,
                .root = &sentinel,
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        fn sibiling(node: *Node) *Node {
            return switch (getParentDirection(node)) {
                .left => node.parent.right,
                .right => node.parent.left,
            };
        }

        /// debug function
        pub fn checkForCycles(self: Self, allocator: std.mem.Allocator) !bool {
            if (self.root == &sentinel) {
                return false;
            }

            var visited = std.AutoHashMap(*Node, void).init(allocator);
            defer visited.deinit();
            return checkForCyclesInternal(self.root, &visited);
        }

        pub fn checkForCyclesInternal(current: *Node, visited: *std.AutoHashMap(*Node, void)) !bool {
            if (current == &sentinel) {
                return false;
            }

            try visited.put(current, void{});

            if (visited.contains(current.left)) {
                std.log.err("found cycle inducer {}", .{current.range});
                std.log.err("connected to (bad child) {}", .{current.left.range});
                std.log.err("connected to {} (is sentinel {})", .{ current.right.range, current.right == &sentinel });
                std.log.err("parent: {}", .{current.parent.range});

                return true;
            }

            if (visited.contains(current.right)) {
                std.log.err("found cycle inducer {}", .{current.range});
                std.log.err("connected to {} (is sentinel {})", .{ current.left.range, current.left == &sentinel });
                std.log.err("connected to (bad child) {}", .{current.right.range});
                std.log.err("parent: {}", .{current.parent.range});
                return true;
            }

            return try checkForCyclesInternal(current.left, visited) or try checkForCyclesInternal(current.right, visited);
        }

        pub fn search(self: Self, range: T, results: *std.ArrayList(T)) !void {
            if (self.root == &sentinel) {
                return;
            }

            return self.searchInternal(range, self.root, results);
        }

        fn searchInternal(self: Self, range: T, current: *Node, results: *std.ArrayList(T)) !void {
            if (current == &sentinel) {
                return;
            }

            if (current.left != &sentinel) {
                try self.searchInternal(range, current.left, results);
            }

            if (rangesIntersect(current.range, range)) {
                try results.append(current.range);
            }

            if (current.right != &sentinel and range.rawStart() <= current.max_end) {
                try self.searchInternal(range, current.right, results);
            }
        }

        fn compare(lhs: T, rhs: T) std.math.Order {
            if (lhs.rawStart() < rhs.rawStart()) {
                return .lt;
            }

            if (lhs.rawStart() > rhs.rawStart()) {
                return .gt;
            }

            if (lhs.rawEnd() < rhs.rawEnd()) {
                return .lt;
            }

            if (lhs.rawEnd() > rhs.rawEnd()) {
                return .lt;
            }

            return .eq;
        }

        pub fn successor(node: *Node) ?*Node {
            if (node.right != &sentinel) {
                var result: *Node = node.right;
                while (result.left != &sentinel) result = result.left;
                return result;
            } else {
                var result: *Node = node;
                while (result != &sentinel and !isLeftChild(result)) result = result.parent;
                if (result == &sentinel) return null;
                return result.parent;
            }
        }

        fn isLeftChild(node: *Node) bool {
            return node == node.parent.left;
        }

        fn restoreBlackProperty(self: *Self, to_fix: *Node) void {
            if (sibiling(to_fix).color == .red) {
                self.rotateUp(sibiling(to_fix));
            }

            if (insideChild(sibiling(to_fix)).color != .red and outsideChild(sibiling(to_fix)).color != .red) {
                sibiling(to_fix).color = .red;

                if (to_fix.parent.color == .red) {
                    to_fix.parent.color = .black;
                } else if (to_fix.parent != self.root) {
                    self.restoreBlackProperty(to_fix.parent);
                }
            } else {
                const far_nephew = outsideChild(sibiling(to_fix));
                if (far_nephew.color != .red) {
                    self.rotateUp(far_nephew);
                }

                self.rotateUp(sibiling(to_fix));

                uncle(to_fix).color = .black;
            }
        }

        pub fn delete(self: *Self, range: T) !void {
            var to_delete = self.root;

            while (to_delete != &sentinel) {
                to_delete = switch (compare(range, to_delete.range)) {
                    .lt => to_delete.left,
                    .gt => to_delete.right,
                    .eq => break,
                };
            }

            if (to_delete == &sentinel) {
                return error.NoSuchKey;
            }

            if (to_delete.left != &sentinel and to_delete.right != &sentinel) {
                to_delete.range = successor(to_delete).?.range;
                to_delete = successor(to_delete).?;
            }

            if (to_delete != self.root and to_delete.color != .red) {
                to_delete.color = .white;
                self.restoreBlackProperty(to_delete);
            }

            const child = if (to_delete.left != &sentinel) to_delete.left else to_delete.right;

            self.setChild(to_delete.parent, child, getParentDirection(to_delete));

            self.arena.allocator().destroy(to_delete);
        }

        pub fn insert(self: *Self, range: T) !void {
            var new_node = try self.arena.allocator().create(Node);

            new_node.* = Node{
                .range = range,
                .max_end = range.rawEnd(),
                .color = .red,
                .left = &sentinel,
                .right = &sentinel,
                .parent = &sentinel,
            };

            if (self.root == &sentinel) {
                new_node.color = .black;
                self.root = new_node;

                return;
            }

            var current = self.root;
            var parent: ?*Node = null;

            while (current != &sentinel) {
                parent = current;

                current = switch (compare(range, current.range)) {
                    .lt => current.left,
                    .gt => current.right,
                    .eq => return error.DuplicateKey,
                };
            }

            if (parent) |p| {
                new_node.parent = p;

                switch (compare(range, parent.?.range)) {
                    .lt => p.left = new_node,
                    .gt => p.right = new_node,
                    .eq => return error.DuplicateKey,
                }
            } else {
                self.root = current;
            }

            if (violatesRedProperty(new_node)) {
                self.restoreRedProperty(new_node);
            }

            if (builtin.mode == .Debug) {
                if (try self.checkForCycles(self.arena.allocator())) {
                    @panic("shit.");
                }
            }
            recalculateMaxEnd(new_node.parent);
        }

        fn violatesRedProperty(node: *Node) bool {
            // `sentinel`'s color is black.
            return node.color == .red and node.parent.color == .red;
        }

        fn uncle(node: *Node) *Node {
            return switch (getParentDirection(node.parent)) {
                .left => node.parent.parent.right,
                .right => node.parent.parent.left,
            };
        }

        fn getParentDirection(node: *Node) Direction {
            if (node == &sentinel) {
                return .right;
            }

            if (node == node.parent.left) {
                return .left;
            } else {
                return .right;
            }
        }

        fn insideChild(node: *Node) *Node {
            return switch (getParentDirection(node)) {
                .left => node.right,
                .right => node.left,
            };
        }

        fn outsideChild(node: *Node) *Node {
            return switch (getParentDirection(node)) {
                .left => node.left,
                .right => node.right,
            };
        }

        fn isInsideChild(node: *Node) bool {
            return getParentDirection(node) != getParentDirection(node.parent);
        }

        const Direction = enum {
            left,
            right,

            pub fn opposite(self: Direction) Direction {
                return switch (self) {
                    .left => .right,
                    .right => .left,
                };
            }
        };

        fn setChild(self: *Self, node: *Node, child: *Node, dir: Direction) void {
            if (node == &sentinel) {
                self.root = child;
            } else {
                switch (dir) {
                    .left => node.left = child,
                    .right => node.right = child,
                }
            }

            if (child != &sentinel) {
                child.parent = node;
            }
        }

        fn rotateUp(self: *Self, node: *Node) void {
            std.mem.swap(Color, &node.color, &node.parent.color);

            const node_dir = getParentDirection(node);
            const parent = node.parent;

            self.setChild(node.parent, insideChild(node), node_dir);
            self.setChild(node.parent.parent, node, getParentDirection(node.parent));
            self.setChild(node, parent, node_dir.opposite());

            recalculateMaxEnd(parent);
        }

        fn restoreRedProperty(self: *Self, node: *Node) void {
            if (node.parent == self.root) {
                // case 1
                node.parent.color = .black;
            } else if (uncle(node).color == .red) {
                // case 2
                node.parent.color = .black;
                uncle(node).color = .black;
                node.parent.parent.color = .red;

                if (violatesRedProperty(node.parent.parent)) {
                    self.restoreRedProperty(node.parent.parent);
                }
            } else {
                // case 3
                var to_rotate = node;
                if (isInsideChild(node)) {
                    self.rotateUp(node);
                    to_rotate = outsideChild(node);
                }

                self.rotateUp(to_rotate.parent);
            }
        }

        fn recalculateMaxEnd(curr: *Node) void {
            var max = curr.max_end;

            if (curr.right != &sentinel) {
                if (curr.right.max_end > max) {
                    max = curr.right.max_end;
                }
            }

            if (curr.left != &sentinel) {
                if (curr.left.max_end > max) {
                    max = curr.left.max_end;
                }
            }

            curr.max_end = max;

            if (curr.parent != &sentinel) {
                recalculateMaxEnd(curr.parent);
            }
        }

        fn writeAllNodes(current: *Node, visited: *std.AutoHashMap(*Node, void), writer: anytype) !void {
            if (current == &sentinel) {
                return;
            }

            if (visited.contains(current)) {
                return;
            }

            visited.put(current, void{}) catch @panic("OOM and I can't return this.");

            const color = switch (current.color) {
                .black => "black",
                .red => "red",
                .white => "white",
            };

            try writer.print("  \"{*}\" [label=\"({}-{}, {}, {})\" color={s}]\n", .{
                current,
                current.range.start,
                current.range.end,
                current.max_end,
                getParentDirection(current),
                color,
            });

            if (current.left != &sentinel) {
                try writer.print("  \"{*}\" -> \"{*}\"\n", .{ current, current.left });
            }

            if (current.right != &sentinel) {
                try writer.print("  \"{*}\" -> \"{*}\"\n", .{ current, current.right });
            }

            try writeAllNodes(current.left, visited, writer);
            try writeAllNodes(current.right, visited, writer);
        }

        pub fn format(
            self: Self,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) std.os.WriteError!void {
            try writer.writeAll("digraph tree {\n");

            var visited = std.AutoHashMap(*Node, void).init(std.heap.page_allocator);
            defer visited.deinit();

            if (self.root != &sentinel) {
                try writeAllNodes(self.root, &visited, writer);
            }

            try writer.writeAll("}\n");
        }
    };
}

const Range = struct {
    start: usize,
    end: usize,

    const Point = usize;

    pub fn rawStart(self: Range) usize {
        return self.start;
    }

    pub fn rawEnd(self: Range) usize {
        return self.end;
    }

    pub fn lessThan(_: void, self: Range, other: Range) bool {
        if (self.start == other.start) {
            return self.end < other.end;
        }

        return self.start < other.start;
    }
};

test "interval tree" {
    const allocator = std.testing.allocator;

    var interval_tree = IntervalTree(Range).init(allocator);
    defer interval_tree.deinit();

    try interval_tree.insert(.{ .start = 7, .end = 20 });
    try interval_tree.insert(.{ .start = 6, .end = 10 });
    try interval_tree.insert(.{ .start = 4, .end = 6 });
    try interval_tree.insert(.{ .start = 3, .end = 5 });

    var results = std.ArrayList(Range).init(allocator);
    defer results.deinit();

    {
        try interval_tree.search(.{ .start = 3, .end = 5 }, &results);
        std.sort.block(Range, results.items, void{}, Range.lessThan);

        try std.testing.expectEqualSlices(Range, results.items, &.{
            Range{ .start = 3, .end = 5 },
            Range{ .start = 4, .end = 6 },
        });

        results.clearRetainingCapacity();
    }

    {
        try interval_tree.search(.{ .start = 6, .end = 7 }, &results);
        std.sort.block(Range, results.items, void{}, Range.lessThan);

        try std.testing.expectEqualSlices(Range, results.items, &.{
            Range{ .start = 4, .end = 6 },
            Range{ .start = 6, .end = 10 },
            Range{ .start = 7, .end = 20 },
        });

        results.clearRetainingCapacity();
    }

    {
        try interval_tree.search(.{ .start = 2, .end = 3 }, &results);
        std.sort.block(Range, results.items, void{}, Range.lessThan);

        try std.testing.expectEqualSlices(Range, results.items, &.{
            Range{ .start = 3, .end = 5 },
        });

        results.clearRetainingCapacity();
    }

    {
        try interval_tree.search(.{ .start = 0, .end = 0 }, &results);
        try std.testing.expectEqualSlices(Range, results.items, &.{});

        results.clearRetainingCapacity();
    }

    try std.testing.expectError(error.NoSuchKey, interval_tree.delete(Range{ .start = 4, .end = 5 }));

    {
        try interval_tree.delete(.{ .start = 3, .end = 5 });

        try interval_tree.search(.{ .start = 3, .end = 5 }, &results);
        std.sort.block(Range, results.items, void{}, Range.lessThan);
        try std.testing.expectEqualSlices(Range, results.items, &.{
            Range{ .start = 4, .end = 6 },
        });

        results.clearRetainingCapacity();
    }

    // TODO: add tests on structure.
}

test "interval tree bench/fuzzing" {
    const RndGen = std.rand.DefaultPrng;

    const allocator = std.testing.allocator;
    const inserts_num = 1000;
    const queries_num = 500;
    const seed: ?u64 = null;

    const alternative = std.crypto.random.int(u64);
    var rnd = RndGen.init(seed orelse alternative);

    std.debug.print("using seed {}\n", .{seed orelse alternative});

    var inserts: [inserts_num]Range = undefined;
    var queries: [queries_num]Range = undefined;

    rnd.fill(std.mem.sliceAsBytes(&inserts));
    rnd.fill(std.mem.sliceAsBytes(&queries));

    for (&inserts) |*insert| {
        insert.start %= insert.end;
    }

    for (&queries) |*query| {
        query.start %= query.end;
    }

    var interval_tree = IntervalTree(Range).init(allocator);
    defer interval_tree.deinit();

    var results = std.ArrayList(Range).init(allocator);
    defer results.deinit();

    const start = try std.time.Instant.now();

    for (inserts) |insert| {
        try interval_tree.insert(insert);
        if (builtin.mode == .Debug) {
            _ = try interval_tree.checkForCycles(allocator);
        }
    }

    const insertion_end = try std.time.Instant.now();

    _ = try interval_tree.checkForCycles(allocator);

    const query_start = try std.time.Instant.now();

    for (queries) |query| {
        try interval_tree.search(query, &results);
        results.clearRetainingCapacity();
    }

    const query_end = try std.time.Instant.now();

    const now = try std.time.Instant.now();
    std.debug.print("total {}. {} per insertion; {} per query\n", .{
        std.fmt.fmtDuration(now.since(start)),
        std.fmt.fmtDuration(insertion_end.since(start) / inserts_num),
        std.fmt.fmtDuration(query_end.since(query_start) / queries_num),
    });
}
