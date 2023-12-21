const std = @import("std");
const egg = @import("egg.zig");

const ToyLanguage = union(enum) {
    add: [2]egg.Id,
    sub: [2]egg.Id,
    constant: usize,

    pub fn getChildren(self: ToyLanguage) ?[]const egg.Id {
        return switch (self) {
            .add => self.add[0..],
            .sub => self.sub[0..],
            else => null,
        };
    }

    pub fn getMutableChildren(self: *ToyLanguage) ?[]egg.Id {
        return switch (self.*) {
            .add => &self.add,
            .sub => &self.sub,
            else => null,
        };
    }
};

test "(add a a)" {
    const allocator = std.testing.allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    var const1 = try egraph.addEclass(.{ .constant = 16 });
    // var const2 = try egraph.addEclass(.{ .constant = 18 });
    _ = try egraph.addEclass(.{ .add = .{ const1, const1 } });

    const Program = egg.Program(ToyLanguage);

    var pattern = Program.patternAst{
        .Enode = .{
            .op = ToyLanguage{ .add = [2]u32{ 1, 2 } },
            .children = &.{ .{ .Symbol = 0 }, .{ .Symbol = 0 } },
        },
    };

    var program = try Program.compile(pattern);

    var vm = egg.Machine(ToyLanguage).init(program);
    defer vm.deinit();

    var results = egg.MatchResultsArray.init(allocator);
    defer results.deinit(allocator);

    defer program.deinit(allocator);

    for (egraph.eclasses.keys()) |eclass| {
        vm.run(egraph, &results, eclass, allocator) catch {};
    }

    std.debug.print("results: {any}\n", .{results.value.items});
}
