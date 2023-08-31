//! a simple union-find structure.
//!
//! this has taken much inspiration from egglog's implementation.

const std = @import("std");

const egg = @import("../egg.zig");
const Id = egg.Id;

const UnionFind = @This();

parents: std.ArrayList(Id),

pub fn init(allocator: std.mem.Allocator) UnionFind {
    return UnionFind{
        .parents = std.ArrayList(Id).init(allocator),
    };
}

pub fn deinit(self: *UnionFind) void {
    self.parents.deinit();
}

pub fn makeSet(self: *UnionFind) !Id {
    const res_id: Id = @intCast(self.parents.items.len);
    try self.parents.append(res_id);

    return res_id;
}

/// find the representative of `id`'s set
pub fn find(self: UnionFind, id: Id) Id {
    var current = id;

    // the root has its parent set to itself
    while (true) {
        const next = self.parents.items[current];
        if (next == current) {
            return current;
        }

        // path halving, cache the possible jump
        const grand = self.parents.items[next];
        self.parents.items[current] = grand;

        current = grand;
    }

    return current;
}

/// merge b into a, returns true if b was reparented
pub fn merge(self: *UnionFind, a: Id, b: Id) bool {
    const rep1 = self.find(a);
    const rep2 = self.find(b);
    self.parents.items[rep2] = rep1;

    return rep1 != rep2;
}

test "unionfind" {
    const n = 10;

    var unionfind = UnionFind.init(std.testing.allocator);
    defer unionfind.deinit();

    for (0..n) |_| {
        _ = try unionfind.makeSet();
    }

    try std.testing.expectEqual(@as(usize, n), unionfind.parents.items.len);

    // first set
    _ = unionfind.merge(0, 1);
    _ = unionfind.merge(0, 2);
    _ = unionfind.merge(0, 3);

    // build another set
    _ = unionfind.merge(6, 7);
    _ = unionfind.merge(6, 8);
    _ = unionfind.merge(6, 9);

    // should compress all paths
    for (0..n) |i| {
        _ = unionfind.find(@intCast(i));
    }

    try std.testing.expectEqualSlices(Id, &.{ 0, 0, 0, 0, 4, 5, 6, 6, 6, 6 }, unionfind.parents.items);
}
