const std = @import("std");
const egg = @import("egg.zig");
const machine = @import("machine.zig");

const ToyLanguage = union(enum) {
    add: [2]egg.Id,
    sub: [2]egg.Id,
    mul: [2]egg.Id,
    constant: usize,

    pub fn getChildren(self: *const ToyLanguage) []const egg.Id {
        return switch (self.*) {
            .add => self.add[0..],
            .sub => self.sub[0..],
            .mul => self.mul[0..],
            else => &.{},
        };
    }

    pub fn getMutableChildren(self: *ToyLanguage) []egg.Id {
        return switch (self.*) {
            .add => self.add[0..],
            .sub => self.sub[0..],
            .mul => self.mul[0..],
            else => &.{},
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

    try std.testing.expectEqual(results.len, 1);
    try std.testing.expectEqual(results[0].root, 1);

    var iter = results[0].matches.iterator();
    while (iter.next()) |entry| {
        try std.testing.expectEqual(entry.key_ptr.*, 0);
        try std.testing.expectEqual(entry.value_ptr.*, 0);
    }

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
    const add = try egraph.addEclass(.{ .add = .{ const1, const1 } });

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

    try std.testing.expectEqualSlices(
        ToyLanguage,
        &.{ ToyLanguage{ .add = .{ 0, 0 } }, ToyLanguage{ .mul = .{ 2, 0 } } },
        egraph.get(add).?.nodes.items,
    );
}
