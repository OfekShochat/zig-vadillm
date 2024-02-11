const std = @import("std");

pub const UnionFind = @import("UnionFind.zig");
pub const EGraph = @import("egraph.zig").EGraph;
pub const Rewrite = @import("egraph.zig").Rewrite;
pub const Program = @import("machine.zig").Program;
pub const Machine = @import("machine.zig").Machine;

comptime {
    _ = @import("tests.zig");
}

pub const Id = u32;

pub const Match = struct { symbol: usize, id: Id };
pub const Substitution = []const Match;

pub const MatchResultsArray = struct {
    value: std.ArrayList(Substitution),

    pub fn init(allocator: std.mem.Allocator) MatchResultsArray {
        return MatchResultsArray{
            .value = std.ArrayList(Substitution).init(allocator),
        };
    }

    pub fn deinit(self: *MatchResultsArray, allocator: std.mem.Allocator) void {
        for (self.value.items) |subs| {
            allocator.free(subs);
        }

        self.results.deinit();
    }

    pub fn append(self: *MatchResultsArray, subs: Substitution) !void {
        try self.value.append(subs);
    }
};
