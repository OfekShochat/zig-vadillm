const std = @import("std");
const egg = @import("../egg.zig");
const UnionFind = @import("UnionFind.zig").UnionFind;

pub fn EGraph(comptime L: type) EGraph {
    return struct {
        language: L,
        memo: std.AutoHashMap(L, egg.Id),
        unionFind: UnionFind,
        EClasses: std.AutoHashMap(egg.Id, L),
    };
}
