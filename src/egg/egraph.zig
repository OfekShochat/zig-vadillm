const std = @import("std");

const egg = @import("../egg.zig");
const machine = @import("machine.zig");
const UnionFind = egg.UnionFind;

pub fn Rewrite(comptime L: type) type {
    return struct {
        pub const Program = egg.Program(L);
        const LT = @typeInfo(L).Union.tag_type.?;

        pub const AstNode = union(enum) {
            enode: L,
            symbol: usize,
        };

        program: Program,
        subst_ast: []const AstNode,
    };
}

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
        const Id = egg.Id;

        union_find: UnionFind,
        eclasses: std.AutoArrayHashMap(Id, EClass),
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
            parents: std.AutoArrayHashMapUnmanaged(L, Id) = .{},
            nodes: std.ArrayListUnmanaged(L),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .union_find = UnionFind.init(allocator),
                .eclasses = std.AutoArrayHashMap(Id, EClass).init(allocator),
                .memo = std.AutoHashMap(L, Id).init(allocator),
                .dirty_ids = std.ArrayList(Id).init(allocator),
                .dirty = false,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.dirty_ids.deinit();
            self.memo.deinit();
            for (self.eclasses.values()) |*eclass| {
                eclass.parents.deinit(self.allocator);
                eclass.nodes.deinit(self.allocator);
            }
            self.eclasses.deinit();
            self.union_find.deinit();
        }

        pub fn get(self: @This(), id: Id) ?*EClass {
            return self.eclasses.getPtr(id);
        }

        pub fn addEclass(self: *@This(), first_enode: L) !Id {
            var enode = first_enode;
            if (self.lookup(&enode)) |existing| {
                return existing;
            }

            const id = try self.union_find.makeSet();

            var nodes = std.ArrayListUnmanaged(L){};
            try nodes.append(self.allocator, enode);

            const eclass = EClass{ .nodes = nodes, .ctx = .{} };

            if (enode.getMutableChildren()) |children| {
                for (children) |child| {
                    var eclass_child = self.eclasses.getPtr(child) orelse @panic("a saved enode's child is invalid.");
                    try eclass_child.parents.put(self.allocator, enode, id);
                }
            }

            try self.eclasses.put(id, eclass);
            try self.memo.putNoClobber(enode, id);

            // here can call a callback?
            self.dirty = true;

            return id;
        }

        const RewriteMatches = struct {
            subst_ast: []const Rewrite(L).AstNode,
            matches: []machine.MatchResult,
        };

        pub fn saturate(self: *@This(), rewrites: []const Rewrite(L), max_iter: usize) !void {
            var results = std.ArrayList(RewriteMatches).init(self.allocator);
            defer results.deinit();

            self.dirty = true;

            var iters: usize = 0;
            while (self.dirty and iters < max_iter) : (iters += 1) {
                self.dirty = false;

                for (rewrites) |rw| {
                    try results.append(.{
                        .subst_ast = rw.subst_ast,
                        .matches = try self.ematch(rw.program),
                    });
                }

                for (results.items) |rw_res| {
                    for (rw_res.matches) |match| {
                        try self.applyRewriteMatches(match.root, rw_res.subst_ast, match.matches);
                    }
                }

                for (results.items) |*res| {
                    for (res.matches) |*match_result| {
                        match_result.matches.deinit();
                    }
                    self.allocator.free(res.matches);
                }

                results.clearAndFree();
                try self.rebuild();
            }
        }

        /// subst_ast has to be in postorder, symbols first.
        fn applyRewriteMatches(
            self: *@This(),
            root: Id,
            subst_ast: []const Rewrite(L).AstNode,
            matches: std.AutoHashMap(usize, Id),
        ) !void {
            // maps a child index of the ast to an Id in the egraph
            var ids = std.ArrayList(Id).init(self.allocator);
            defer ids.deinit();

            try ids.appendNTimes(0, subst_ast.len);

            for (subst_ast, 0..) |node, i| {
                switch (node) {
                    .enode => |enode| {
                        if (enode.getChildren()) |ast_children| {
                            var copied = enode;

                            // for each child, map its id to the actual egraph id
                            for (copied.getMutableChildren().?, ast_children) |*child, ast_id| {
                                child.* = ids.items[ast_id];
                            }

                            ids.items[i] = try self.addEclass(copied);
                        } else {
                            // ground term, add it to the graph and the ids
                            ids.items[i] = try self.addEclass(enode);
                        }
                    },
                    .symbol => |symbol| {
                        ids.items[i] = matches.get(symbol).?;
                    },
                }
            }

            _ = try self.merge(root, ids.items[ids.items.len - 1]);
        }

        pub fn ematch(self: @This(), program: egg.Program(L)) ![]machine.MatchResult {
            var results = std.ArrayList(machine.MatchResult).init(self.allocator);

            var vm = machine.Machine(L).init(program, self.allocator);
            defer vm.deinit();

            for (self.eclasses.keys()) |eclass| {
                try vm.run(self, &results, eclass, self.allocator);
            }

            return @constCast(try results.toOwnedSlice());
        }

        /// updates enode in-place
        fn lookup(self: @This(), enode: *L) ?Id {
            self.canonicalize(enode);
            return self.memo.get(enode.*);
        }

        /// updates enode in-place
        fn canonicalize(self: @This(), enode: *L) void {
            if (enode.getMutableChildren()) |children| {
                for (children) |*child| {
                    child.* = self.find(child.*);
                }
            }
        }

        fn merge(self: *@This(), a: Id, b: Id) !Id {
            if (self.find(a) == self.find(b)) {
                return self.find(a);
            }

            _ = self.union_find.merge(a, b);
            try self.dirty_ids.append(a); // submit a pending enode to repair


            var eclass1 = self.eclasses.getPtr(a).?;
            var eclass2 = self.eclasses.getPtr(b).?;
            try eclass1.nodes.appendSlice(self.allocator, try eclass2.nodes.toOwnedSlice(self.allocator));

            var iter = eclass2.parents.iterator();
            while (iter.next()) |entry| {
                try eclass1.parents.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
            }

            const removed = self.eclasses.orderedRemove(b);
            std.debug.assert(removed);

            return a;
        }

        pub fn find(self: @This(), id: Id) Id {
            return self.union_find.find(id);
        }

        fn repair(self: *@This(), eclass_id: Id) !void {
            var eclass = self.eclasses.getPtr(eclass_id).?;

            var iter = eclass.parents.iterator();
            while (iter.next()) |entry| {
                var parent = entry.key_ptr;

                std.debug.assert(self.memo.remove(parent.*));
                self.canonicalize(parent);

                try self.memo.putNoClobber(
                    parent.*,
                    self.find(entry.value_ptr.*),
                );
            }

            var visited_parents = std.AutoArrayHashMap(L, Id).init(self.allocator);

            iter = eclass.parents.iterator();
            while (iter.next()) |entry| {
                var parent = entry.key_ptr;
                self.canonicalize(parent);

                if (visited_parents.get(parent.*)) |visited_parent| {
                    _ = try self.merge(entry.value_ptr.*, visited_parent);
                }

                try visited_parents.put(parent.*, self.find(entry.value_ptr.*));
            }

            eclass.parents.deinit(self.allocator);
            eclass.parents = visited_parents.unmanaged;
        }

        fn rebuild(self: *@This()) !void {
            while (self.dirty_ids.items.len > 0) {
                var todo = try self.dirty_ids.toOwnedSlice();
                for (todo) |eclass| {
                    try self.repair(self.find(eclass));
                }
            }
        }
    };
}
