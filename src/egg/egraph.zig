const std = @import("std");

const egg = @import("../egg.zig");
const UnionFind = egg.UnionFind;
const Id = egg.Id;

/// An Egraph representation.
///
/// T: the enode type
/// C: the context type that will be present in every eclass
///
/// # Example
///
/// ```
/// const egraph = @import("egraph.zig");
/// const Egraph = egraph.Egraph;
/// ...
///
/// // has to be a union
/// pub const EgraphNode = union {
///     add: [2]egraph.Id,
///     sub: [2]egraph.Id,
///     constant: []const u8,
/// };
///
/// pub const EClassContext = struct {
///     orig_value: ?Index,
///     evaluated: ?Constant,
/// };
///
/// var egraph = Egraph(EgraphNode, EClassContext).init(allocator);
///
/// var const1 = egraph.addEClass(EgraphNode{.constant = &{1}});
/// var const2 = egraph.addEClass(EgraphNode{.constant = &{2});
/// egraph.addEClass(EgraphNode{.add = .{const1, const2}});
///
/// ...
/// ```
pub fn EGraph(comptime L: type, comptime C: type) type {
    return struct {
        union_find: UnionFind,
        eclasses: std.AutoHashMap(Id, EClass),
        memo: std.AutoHashMap(L, Id),
        dirty_ids: std.ArrayList(Id),
        dirty: bool,
        allocator: std.mem.Allocator,

        comptime {
            if (!std.meta.trait.is(.Union)(L)) {
                @compileError("`L` has to be a union to qualify to be a Language.");
            }
        }

        const PendingEntry = struct {
            id: Id,
            eclass: EClass,
        };

        pub const EClass = struct {
            // dude how do I not save the enode itself it feels shit
            children: std.AutoArrayHashMapUnmanaged(L, Id) = .{},
            nodes: std.ArrayListUnmanaged(L),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .union_find = UnionFind.init(allocator),
                .eclasses = std.AutoHashMap(Id, EClass).init(allocator),
                .memo = std.AutoHashMap(L, Id).init(allocator),
                .dirty_ids = std.ArrayList(Id).init(allocator),
                .dirty = false,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.dirty_ids.deinit();
            self.memo.deinit();
            var iter = self.eclasses.valueIterator();
            while (iter.next()) |eclass| {
                eclass.children.deinit(self.allocator);
                eclass.nodes.deinit(self.allocator);
            }
            self.eclasses.deinit();
            self.union_find.deinit();
        }

        fn lookup(self: @This(), enode: *L) ?Id {
            self.canonicalize(enode);
            return self.memo.get(enode.*);
        }

        pub fn get(self: @This(), id: Id) ?*EClass {
            return self.eclasses.getPtr(id);
        }

        fn addEclass(self: *@This(), first_enode: L) !Id {
            var enode = first_enode;
            if (self.lookup(&enode)) |existing| {
                return existing;
            }

            const id = try self.union_find.makeSet();

            var nodes = std.ArrayListUnmanaged(L){};
            try nodes.append(self.allocator, enode);

            const eclass = EClass{ .nodes = nodes, .ctx = .{} };

            if (enode.children()) |children| {
                for (children) |child| {
                    var eclass_child = self.eclasses.getPtr(child) orelse @panic("a saved enode's child is invalid.");
                    try eclass_child.children.put(self.allocator, enode, id);
                }
            }

            try self.eclasses.put(id, eclass);
            try self.memo.putNoClobber(enode, id);

            // here can call a callback?
            self.dirty = true;

            return id;
        }

        pub fn canonicalize(self: @This(), enode: *L) void {
            if (enode.children()) |children| {
                for (children) |*child| {
                    child.* = self.union_find.find(child.*);
                }
            }
        }

        fn merge(self: *@This(), a: Id, b: Id) !Id {
            if (self.union_find.find(a) == self.union_find.find(b)) {
                return self.union_find.find(a);
            }

            const new_id = self.union_find.merge(a, b);
            try self.dirty_ids.append(new_id);

            return new_id;
        }

        fn repair(self: *@This(), eclass_id: Id) void {
            var eclass = self.eclasses.getPtr(eclass_id).?;
            for (eclass.children.items) |parent| {
                std.debug.assert(self.memo.remove(parent.enode));
                self.canonicalize(&parent.enode);

                try self.memo.putNoClobber(
                    parent.enode,
                    self.union_find.find(parent.eclass_id),
                );
            }

            var visited_children = std.AutoArrayHashMap(L, Id).init(self.allocator);

            for (eclass.children.items) |parent| {
                if (visited_children.contains(parent.enode)) {
                    try self.merge(parent.eclass_id, visited_children.get(parent.enode));
                }

                try visited_children.put(parent.enode, self.union_find.find(parent.eclass_id));
            }

            eclass.children.deinit();
            eclass.children = visited_children.unmanaged;
        }

        pub fn find(self: @This(), id: Id) Id {
            return self.union_find.find(id);
        }

        fn rebuild(self: *@This()) void {
            while (self.dirty_ids.items.len > 0) {
                var todo = try self.dirty_ids.toOwnedSlice();
                for (todo) |eclass| {
                    self.repair(self.union_find.find(eclass));
                }
            }
        }
    };
}

const Test = union(enum) {
    stuff: [2]Id,
};

test "egraph" {
    var poop = Test{ .stuff = .{ 1, 2 } };
    var a = switch (poop) {
        .stuff => |*stuff| stuff,
    };

    a[0] = 2;

    std.log.err("{any}", .{poop.stuff});
}

const ToyLanguage = union(enum) {
    add: [2]egg.Id,
    sub: [2]egg.Id,
    constant: usize,

    pub fn childrenConst(self: ToyLanguage) ?[]const egg.Id {
        return switch (self) {
            .add => self.add[0..],
            .sub => self.sub[0..],
            else => null,
        };
    }

    pub fn children(self: *ToyLanguage) ?[]egg.Id {
        return switch (self.*) {
            .add => &self.add,
            .sub => &self.sub,
            else => null,
        };
    }
};

test "ematching" {
    const allocator = std.testing.allocator;
    var egraph = EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    var const1 = try egraph.addEclass(.{ .constant = 16 });
    var const2 = try egraph.addEclass(.{ .constant = 18 });
    const root = try egraph.addEclass(.{ .add = .{ const1, const2 } });

    const machine = @import("machine.zig");
    const Program = machine.Program(ToyLanguage);

    var pattern = Program.PatternAst{
        .enode = .{
            .op = .{ .add = .{ 0, 1 } },
            .children = &.{.{ .symbol = 0}, .{ .symbol = 1}},
        },
    };

    var program = try Program.compileFrom(allocator, pattern);
    var actual = machine.Machine(ToyLanguage).init(program, allocator);
    var results = std.ArrayList(machine.Substitution).init(allocator);
    defer results.deinit();
    defer actual.deinit();
    defer program.deinit(allocator);
    try actual.run(egraph, &results, root, allocator);

    std.debug.print("{any}\n", .{results.items});
}
