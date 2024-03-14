const std = @import("std");
const egg = @import("../egg.zig");
const machine = @import("machine.zig");

const ToyLanguage = union(enum) {
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
};

test "(add a a)" {
    const allocator = std.testing.allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    const const1 = try egraph.addEclass(.{ .constant = 16 });
    // var const2 = try egraph.addEclass(.{ .constant = 18 });
    _ = try egraph.addEclass(.{ .add = .{ const1, const1 } });

    const Program = egg.Program(ToyLanguage);

    const pattern = Program.PatternAst{
        .enode = .{
            .op = .add,
            .children = &.{ .{ .symbol = 0 }, .{ .symbol = 0 } },
        },
    };

    var program = try Program.compileFrom(allocator, pattern);
    defer program.deinit(allocator);

    const results = try egraph.ematch(program);
    std.debug.print("results: {any}\n", .{results});

    for (results) |*res| {
        res.matches.deinit();
    }
    allocator.free(results);
}

test "saturate (add a a)" {
    const allocator = std.testing.allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    const const1 = try egraph.addEclass(.{ .constant = 16 });
    // var const2 = try egraph.addEclass(.{ .constant = 18 });
    _ = try egraph.addEclass(.{ .add = .{ const1, const1 } });

    const Program = egg.Program(ToyLanguage);

    const pattern = Program.PatternAst{
        .enode = .{
            .op = .add,
            .children = &.{ .{ .symbol = 0 }, .{ .symbol = 0 } },
        },
    };

    var program = try Program.compileFrom(allocator, pattern);
    defer program.deinit(allocator);

    const rewrites = [1]egg.Rewrite(ToyLanguage){egg.Rewrite(ToyLanguage){
        .program = program,
        .subst_ast = &.{ .{ .symbol = 0 }, .{ .enode = .{ .constant = 2 } }, .{ .enode = .{ .mul = .{ 1, 0 } } } },
    }};

    try egraph.saturate(&rewrites, 3);

    var iter = egraph.eclasses.iterator();
    while (iter.next()) |entry| {
        std.debug.print("{} {any}\n", .{ entry.key_ptr.*, entry.value_ptr.nodes.items });
    }
}
