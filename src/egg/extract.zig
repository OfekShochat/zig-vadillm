const EGraph = @import("egraph.zig").EGraph;
const egg = @import("egg.zig");
const std = @import("std");
const ToyLanguage = @import("tests.zig").ToyLanguage;

pub fn extract(comptime L: type) type {
    return struct {
        eclass: egg.Id,
        partialExp: std.ArrayList(L),
        eclass_stack: std.ArrayList(egg.Id),

        const enode_cost_pair = struct { cost: usize, enode: L };

        fn eval_eclass_min_cost(self: *@This(), eclass_id: egg.Id, egraph: anytype) !enode_cost_pair {
            var enodes = egraph.get(eclass_id).?.*.nodes.items;
            var min_enode = enodes[0];
            var min_cost = enodes[0].getExpressionCost();
            for (0..enodes.len) |i| {
                var enode_cost = enodes[i].getExpressionCost();
                if (enode_cost < min_cost) {
                    min_cost = enodes[i].getExpressionCost();
                    min_enode = enodes[i];
                }
            }

            try self.partialExp.append(min_enode);
            return enode_cost_pair{ .cost = min_cost, .enode = min_enode };
        }

        fn eval_expression_cost(self: *@This(), eclass_id: egg.Id, egraph: anytype) !usize {
            var total_cost: usize = 0;
            var ret_pair = try eval_eclass_min_cost(self, eclass_id, egraph);
            total_cost += ret_pair.cost;
            var children = ret_pair.enode.getMutableChildren();
            for (children orelse return total_cost) |child| {
                try self.eclass_stack.append(child);
                std.log.warn("push child into stack: {}\n", .{child});
                //total_cost += try eval_eclass_min_cost(self, child, egraph);
            }

            return total_cost;
        }

        pub fn find_cheapest_expression(self: *@This(), root_eclass: egg.Id, egraph: anytype) !usize {
            var total_cost: usize = 0;

            try self.eclass_stack.append(root_eclass);
            while (true) {
                if (self.eclass_stack.items.len == 0) {
                    break;
                }

                var eclass = self.eclass_stack.popOrNull().?; // eclass_stack.items[eclass_stack.items.len - 1];
                total_cost += try eval_expression_cost(self, eclass, egraph);
                std.log.warn("eclass stack len: {}", .{self.eclass_stack.items.len});
                // for (childrens.children.values()) |children| {
                // std.log.warn("children: {}", .{egraph.get(children).?.*.nodes.items[0]});
                // try eclass_stack.append(children);
                // }
            }

            return total_cost;
        }

        pub fn init(eclass: egg.Id) @This() {
            return @This(){ .eclass = eclass, .partialExp = std.ArrayList(L).init(std.testing.allocator), .eclass_stack = std.ArrayList(egg.Id).init(std.testing.allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.partialExp.deinit();
            self.eclass_stack.deinit();
        }
    };
}

test "extract" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(std.testing.allocator);
    defer egraph.deinit();

    var const1 = try egraph.addEclass(.{ .constant = 16 });
    var const2 = try egraph.addEclass(.{ .constant = 17 });
    // var const2 = try egraph.addEclass(.{ .constant = 18 });
    var expr = try egraph.addEclass(.{ .add = .{ const1, const2 } });
    var extract_obj = extract(ToyLanguage).init(0);
    var cost: usize = try extract_obj.find_cheapest_expression(expr, egraph);
    std.log.warn("cost: {}", .{cost});
    for (extract_obj.partialExp.items) |lang| {
        std.log.warn("obj: {}", .{lang});
    }
    extract_obj.deinit();
}

test "extract recursive" {
    const allocator = std.testing.allocator;
    var egraph = egg.EGraph(ToyLanguage, struct {}).init(allocator);
    defer egraph.deinit();

    var const1 = try egraph.addEclass(.{ .constant = 16 });
    var const2 = try egraph.addEclass(.{ .constant = 17 });
    var add_expr = try egraph.addEclass(.{ .add = .{ const1, const2 } });
    var add_expr2 = try egraph.addEclass(.{ .add = .{ add_expr, const2 } });
    var extract_obj = extract(ToyLanguage).init(0);
    defer extract_obj.deinit();
    var cost: usize = try extract_obj.find_cheapest_expression(add_expr2, egraph);
    std.log.warn("cost: {}", .{cost});
}
