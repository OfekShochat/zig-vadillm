const std = @import("std");

pub const UnionFind = @import("egg/UnionFind.zig");
pub const EGraph = @import("egg/egraph.zig").EGraph;
pub const Rewrite = @import("egg/egraph.zig").Rewrite;
pub const Program = @import("egg/machine.zig").Program;

comptime {
    _ = @import("egg/tests.zig");
}

pub const Id = u32;
