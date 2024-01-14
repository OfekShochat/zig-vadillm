const std = @import("std");
const egg = @import("egg.zig");
const machine = @import("machine.zig");

pub const ToyLanguage = union(enum) {
    add: [2]egg.Id,
    sub: [2]egg.Id,
    mul: [2]egg.Id,
    constant: usize,

    pub fn getChildren(self: ToyLanguage) ?[]const egg.Id {
        return switch (self) {
            .add => self.add[0..],
            .sub => self.sub[0..],
            .mul => self.mul[0..],
            else => null,
        };
    }

    pub fn getMutableChildren(self: *ToyLanguage) ?[]egg.Id {
        return switch (self.*) {
            .add => self.add[0..],
            .sub => self.sub[0..],
            .mul => self.mul[0..],
            else => null,
        };
    }

    pub fn getExpressionCost(self: *ToyLanguage) usize {
        return switch (self.*) {
            .add => 2,
            .sub => 2,
            .mul => 2,
            .constant => 1,
        };
    }
};

test "(add a a)" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    var const1 = try egraph.addEclass(.{ .constant = 16 });
    // var const2 = try egraph.addEclass(.{ .constant = 18 });
    _ = try egraph.addEclass(.{ .add = .{ const1, const1 } });

    const Program = egg.Program(ToyLanguage);

    var pattern = Program.patternAst{
        .Enode = .{
            .op = .add,
            .children = &.{ .{ .Symbol = 0 }, .{ .Symbol = 0 } },
        },
    };
    _ = pattern;

    //var program = try Program.compile(pattern);

    //var vm = egg.Machine(ToyLanguage).init(program);
    //defer vm.deinit();
    // defer vm.deinit();

    //var results = egg.MatchResultsArray.init(allocator);
    // defer results.deinit(allocator);

    //defer program.deinit(allocator);

    for (egraph.eclasses.keys()) |eclass| {
        //vm.run(egraph, &results, eclass, allocator) catch {};
        std.log.warn("\neclass id: {}\n", .{eclass});
        var result = std.AutoArrayHashMap(usize, usize).init(std.testing.allocator);
        defer result.deinit();

        //        var a = try vm.run(&result, 1, egraph);
        //        if (a == true) {
        //            std.log.warn("result: success", .{});
        //        }
        //        std.debug.print("results: {}\n", .{result.values().len});
    }

    //std.debug.print("results: {any}\n", .{results.value.items});
}
