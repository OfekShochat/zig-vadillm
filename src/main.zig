const std = @import("std");
const types = @import("types.zig");
const Type = @import("types.zig").Type;
const mem = std.mem;
const a = @import("DominatorTree.zig");

pub const ValueRef = u32;
pub const BlockRef = u32;
pub const FuncRef = u32;
pub const InstRef = u32;
pub const ConstantRef = u32;
pub const GlobalValueRef = u32;

pub const BinOp = struct { lhs: ValueRef, rhs: ValueRef };

// possible optimization, use [*] and a u8 len becaues we don't have that many registers
pub const BlockCall = struct {
    block: BlockRef,
    args: []ValueRef,
};

pub const CondCode = enum {
    /// `==`
    Equal,
    /// `!=`
    NotEqual,
    /// signed `<`
    SignedLessThan,
    /// signed `>=`
    SignedGreaterThanOrEqual,
    /// signed `>`
    SignedGreaterThan,
    /// signed `<=`
    SignedLessThanOrEqual,
    /// unsigned `<`
    UnsignedLessThan,
    /// unsigned `>=`
    UnsignedGreaterThanOrEqual,
    /// unsigned `>`
    UnsignedGreaterThan,
    /// unsigned `<=`
    UnsignedLessThanOrEqual,
};

pub const Instruction = union(enum) {
    add: BinOp,
    sub: BinOp,
    mul: BinOp,
    shl: BinOp,
    shr: BinOp,

    imm: Constant,

    icmp: struct { cond_code: CondCode, lhs: ValueRef, rhs: ValueRef },

    alloca: struct { size: usize, alignment: usize },

    call: struct {
        func: FuncRef,
        args: []ValueRef,
    },

    brif: struct {
        cond: ValueRef,
        cond_true: BlockCall,
        cond_false: BlockCall,
    },

    jump: BlockCall,

    ret: ?ValueRef,
};

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
/// // ?*Node is given to get the (optional) origin node
/// var egraph = Egraph(EgraphNode, ?*Node).init(allocator);
///
/// var const1 = egraph.add_eclass(EgraphNode{.constant = &{1}});
/// var const2 = egraph.add_eclass(EgraphNode{.constant = &{2});
/// egraph.add_eclass(EgraphNode{.add = .{const1, const2}});
///
/// var pass_ctx = MyPassContext{
///     ...
/// };
///
/// var iter =
///
/// ...
/// ```
pub fn Egraph(comptime T: type, comptime C: type) type {
    return struct {
        nodes: std.AutoHashMap(ValueRef, T),
        allocator: std.mem.Allocator,

        pub const EClass = struct {
            equivalences: std.ArrayListUnmanaged(T),
            ctx: C,
        };

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .nodes = std.AutoHashMap(ValueRef, T).init(allocator),
                .allocator = allocator,
            };
        }
    };
}

pub const GlobalValue = struct {
    name: []const u8,
    initial_value: ConstantRef,
};

// pub const Module = struct {
//     funcs: std.ArrayList(Function),
//     func_decls: HashSet(FunctionDecl),
//     constants: std.ArrayList(Constant),
//     global_values: std.ArrayList(GlobalValue),
//     allocator: mem.Allocator,
//
//     pub fn init(allocator: mem.Allocator) !void {
//         return Module{
//             .funcs = std.ArrayList(Function).init(allocator),
//             .func_decls = std.ArrayList(FunctionDecl).init(allocator),
//             .constants = std.ArrayList(Constant).init(allocator),
//             .global_values = std.ArrayList(GlobalValue).init(allocator),
//             .allocator = allocator,
//         };
//     }
//
//     pub fn deinit(self: *Module) void {
//         for (self.funcs.items) |func| {
//             func.deinit();
//         }
//         self.funcs.deinit();
//         self.func_decls.deinit();
//         self.constants.deinit();
//         self.global_values.deinit();
//     }
//
//     pub fn declareFunction(self: *Module, name: []const u8, signature: Signature) !void {
//         return self.func_decls.put(
//             self.allocator,
//             FunctionDecl{ .name = name, .signature = signature },
//         );
//     }
//
//     pub fn defineFunction(self: *Module, func: Function) !void {
//         return self.funcs.append(func);
//     }
// };

pub const Target = struct {};

pub const Constant = []const u8;

pub const ValueData = union(enum) {
    alias: struct { to: ValueRef },
    param: struct { idx: usize },
    global_value: GlobalValueRef,
    constant: ConstantRef,
    inst: InstRef,
};

pub const Signature = struct {
    ret: Type,
    args: std.ArrayListUnmanaged(Type),

    pub fn deinit(self: *Signature, allocator: mem.Allocator) void {
        self.args.deinit(allocator);
    }

    pub fn format(
        self: Signature,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("(");
        for (self.args.items, 0..) |arg_type, i| {
            try writer.print("{}", .{arg_type});

            if (i < self.args.items.len - 1) {
                try writer.writeAll(", ");
            }
        }
        try writer.print(") {}", .{self.ret});
    }
};

pub fn HashSet(comptime T: type) type {
    return struct {
        inner: std.AutoArrayHashMapUnmanaged(T, void) = .{},

        pub fn deinit(self: *@This(), allocator: mem.Allocator) void {
            self.inner.deinit(allocator);
        }

        pub fn put(self: *@This(), allocator: std.mem.Allocator, val: T) !void {
            return self.inner.put(allocator, val, void{});
        }

        pub fn contains(self: @This(), key: T) bool {
            return self.inner.contains(key);
        }

        pub fn iter(self: *const @This()) []T {
            return self.inner.keys();
        }
    };
}

pub const FunctionDecl = struct {
    name: []const u8,
    signature: Signature,
};
pub const CFGNode = struct {
    preds: HashSet(BlockRef) = .{},
    succs: HashSet(BlockRef) = .{},
};

pub const ControlFlowGraph = struct {
    // TODO: transition to arrayhashmap
    nodes: std.AutoHashMapUnmanaged(BlockRef, CFGNode) = .{},

    pub fn fromFunction(allocator: mem.Allocator, func: *const Function) !ControlFlowGraph {
        var cfg = ControlFlowGraph{};

        var iter = func.blocks.iterator();
        while (iter.next()) |kv| {
            switch (kv.value_ptr.getTerminator()) {
                .brif => |brif| {
                    try cfg.addEdge(allocator, kv.key_ptr.*, brif.cond_true.block);
                    try cfg.addEdge(allocator, kv.key_ptr.*, brif.cond_false.block);
                },
                .jump => |jump| try cfg.addEdge(allocator, kv.key_ptr.*, jump.block),
                else => {},
                // else => try cfg.nodes.put(allocator, kv.key_ptr.*, CFGNode{}),
            }
        }

        return cfg;
    }

    pub fn deinit(self: *ControlFlowGraph, allocator: mem.Allocator) void {
        var iter = self.nodes.valueIterator();
        while (iter.next()) |node| {
            node.preds.deinit(allocator);
            node.succs.deinit(allocator);
        }
        self.nodes.deinit(allocator);
    }

    fn addEdge(self: *ControlFlowGraph, allocator: std.mem.Allocator, from: BlockRef, to: BlockRef) !void {
        std.log.debug("cfg edge: {} {}", .{ from, to });

        var cfg_entry = try self.nodes.getOrPutValue(allocator, from, CFGNode{});
        try cfg_entry.value_ptr.succs.put(allocator, to);

        cfg_entry = try self.nodes.getOrPutValue(allocator, to, CFGNode{});
        try cfg_entry.value_ptr.preds.put(allocator, from);
    }

    pub fn get(self: ControlFlowGraph, block_ref: BlockRef) ?*const CFGNode {
        return self.nodes.getPtr(block_ref);
    }
};

pub const Function = struct {
    name: []const u8,
    signature: Signature,
    allocator: mem.Allocator,
    blocks: std.AutoArrayHashMapUnmanaged(BlockRef, Block) = .{},
    values: ValuePool = .{},
    entry_ref: BlockRef = 0,
    block_counter: BlockRef = 0,

    pub fn init(
        allocator: mem.Allocator,
        name: []const u8,
        signature: Signature,
    ) Function {
        return Function{
            .name = name,
            .signature = signature,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Function, allocator: mem.Allocator) void {
        for (self.blocks.entries.items(.value)) |*b| {
            b.deinit(allocator);
        }

        self.blocks.deinit(allocator);
        self.signature.deinit(allocator);
    }

    pub fn format(
        self: Function,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        // TODO: print calling convention etc here rust derive style

        try writer.print("define {s}{} {{\n", .{ self.name, self.signature });

        var iter = self.blocks.iterator();
        while (iter.next()) |kv| {
            try kv.value_ptr.print(&self.values, kv.key_ptr.*, writer);
        }
    }

    pub fn entryBlock(self: Function) BlockRef {
        return self.entry_ref;
    }

    pub fn appendBlock(self: *Function, allocator: mem.Allocator) mem.Allocator.Error!BlockRef {
        defer self.block_counter += 1;
        try self.blocks.put(allocator, self.block_counter, Block{});

        return self.block_counter;
    }

    pub fn addValue(self: *Function, value: Value) !ValueRef {
        return self.values.put(value);
    }

    pub fn getValue(self: *Function, value_ref: ValueRef) !?*Value {
        return self.values.getPtr(value_ref);
    }

    pub fn appendInst(
        self: *Function,
        allocator: mem.Allocator,
        block_ref: BlockRef,
        inst: Instruction,
        ty: Type,
    ) mem.Allocator.Error!ValueRef {
        if (self.blocks.getPtr(block_ref)) |block| {
            return block.appendInst(allocator, &self.values, inst, ty);
        }

        unreachable;
    }

    pub fn appendBlockParam(self: *Function, allocator: mem.Allocator, block_ref: BlockRef, ty: Type) mem.Allocator.Error!ValueRef {
        if (self.blocks.getPtr(block_ref)) |block| {
            return block.appendParam(allocator, &self.values, ty);
        }

        unreachable;
    }

    pub fn appendParam(self: *Function, allocator: mem.Allocator, ty: Type) mem.Allocator.Error!void {
        return self.signature.args.append(allocator, ty);
    }
};

pub const ValuePool = struct {
    values: ValueMap = .{},
    value_counter: ValueRef = 0,

    const ValueMap = std.AutoArrayHashMapUnmanaged(ValueRef, Value);

    pub fn deinit(self: *ValuePool, allocator: mem.Allocator) void {
        self.values.deinit(allocator);
    }

    pub fn get(self: ValuePool, key: ValueRef) ?*const Value {
        return self.values.getPtr(key);
    }

    pub fn put(self: *ValuePool, allocator: mem.Allocator, value: Value) mem.Allocator.Error!ValueRef {
        defer self.value_counter += 1;
        try self.values.put(allocator, self.value_counter, value);

        return self.value_counter;
    }

    pub fn iterator(self: *const ValuePool) ValueMap.Iterator {
        return self.values.iterator();
    }
};

pub const Block = struct {
    params: std.ArrayListUnmanaged(ValueRef) = .{},
    insts: std.ArrayListUnmanaged(Instruction) = .{},

    pub fn deinit(self: *Block, allocator: mem.Allocator) void {
        self.insts.deinit(allocator);
        self.params.deinit(allocator);
    }

    pub fn print(
        self: *const Block,
        value_pool: *const ValuePool,
        ref: BlockRef,
        writer: anytype,
    ) !void {
        try writer.print("block{}(", .{ref});
        for (self.params.items, 0..) |param_ref, i| {
            try writer.print("{}", .{value_pool.get(param_ref).?.ty});

            if (i < self.params.items.len - 1) {
                try writer.writeAll(", ");
            }
        }

        try writer.writeAll("):\n");

        // for (self.insts.items) |int| {
        //     try writer.print("v{} = {} {}\n", .{ key_ptr.*, kv.value_ptr.ty, kv.value_ptr.data });
        // }
    }

    pub fn appendParam(self: *Block, allocator: mem.Allocator, value_pool: *ValuePool, ty: Type) mem.Allocator.Error!ValueRef {
        const param_ref = try value_pool.put(allocator, Value.init(ValueData{
            .param = .{ .idx = self.params.items.len },
        }, ty));

        try self.params.append(allocator, param_ref);

        return param_ref;
    }

    pub fn appendInst(self: *Block, allocator: mem.Allocator, value_pool: *ValuePool, inst: Instruction, ty: Type) mem.Allocator.Error!ValueRef {
        return self.insertInst(allocator, value_pool, @intCast(self.insts.items.len), inst, ty);
    }

    pub fn insertInstBeforeTerm(
        self: *Block,
        allocator: mem.Allocator,
        value_pool: *ValuePool,
        inst: Instruction,
        ty: Type,
    ) mem.Allocator.Error!ValueRef {
        std.debug.assert(self.insts.items.len > 0);

        return self.insertInst(allocator, value_pool, self.insts.items.len - 1, inst, ty);
    }

    pub fn insertInst(
        self: *Block,
        allocator: mem.Allocator,
        value_pool: *ValuePool,
        before: InstRef,
        inst: Instruction,
        ty: Type,
    ) mem.Allocator.Error!ValueRef {
        std.debug.assert(before <= self.insts.items.len);

        try self.insts.insert(allocator, before, inst);

        return value_pool.put(
            allocator,
            Value.init(ValueData{ .inst = @intCast(before) }, ty),
        );
    }

    pub fn getTerminator(self: Block) Instruction {
        return self.insts.getLast();
    }
};

pub const Value = struct {
    data: ValueData,
    ty: Type,

    pub fn init(data: ValueData, ty: Type) Value {
        return Value{
            .data = data,
            .ty = ty,
        };
    }
};

pub const VerifierError = struct {
    ty: enum {
        Typecheck,
    },
    loc: ValueRef,
    message: []const u8,
};

pub const Verifier = struct {
    // graph: *const Graph,

    pub const ErrorStack = std.ArrayList(VerifierError);

    pub fn init() Verifier {}

    pub fn verify(self: *Verifier, error_stack: *ErrorStack) bool {
        var iter = self.graph.nodes.iterator();
        while (iter) |kv| {
            try self.typecheck(kv.key_ptr.*, error_stack);
        }
    }

    fn typecheck(self: Verifier, node: ValueRef, error_stack: *ErrorStack) !void {
        _ = self;

        try error_stack.append(VerifierError{
            .ty = .Typecheck,
            .loc = node,
            .message = "",
        });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    var func = Function.init(alloc, "add", Signature{
        .ret = types.I32,
        .args = .{},
    });

    defer func.deinit(alloc);

    try func.appendParam(alloc, types.I32);

    var zero_args = try alloc.alloc(ValueRef, 0);

    const b = try func.appendBlock(alloc);
    const b2 = try func.appendBlock(alloc);
    _ = try func.appendInst(
        alloc,
        b,
        Instruction{ .jump = .{ .block = b2, .args = zero_args } },
        types.I32,
    );

    const p1 = try func.appendBlockParam(alloc, b, types.I32);

    _ = try func.appendInst(
        alloc,
        b2,
        Instruction{ .ret = p1 },
        types.I32,
    );

    const cfg = try ControlFlowGraph.fromFunction(alloc, &func);
    // std.log.info("{any}", .{func.blocks.get(0).?.insts.items});
    // std.log.info("{any}", .{func.values.get(ret).?.data});
    // std.log.info("{any}", .{func});
    // std.log.info("{any}", .{cfg});

    var domtree = a{};
    try domtree.compute(alloc, &cfg, &func);
    std.log.info("{any}", .{domtree.formatter(&func)});
}

test "ControlFlowGraph" {
    var allocator = std.testing.allocator;

    var func = Function.init(allocator, "add", Signature{
        .ret = types.I32,
        .args = .{},
    });
    defer func.deinit(allocator);

    try func.appendParam(allocator, types.I32);

    const block1 = try func.appendBlock(allocator);
    const block2 = try func.appendBlock(allocator);
    const param1 = try func.appendBlockParam(allocator, block1, types.I32);

    var block1_args = try allocator.alloc(ValueRef, 0);

    _ = try func.appendInst(
        allocator,
        block1,
        Instruction{ .jump = .{ .block = block2, .args = block1_args } },
        types.I32,
    );

    _ = try func.appendInst(
        allocator,
        block2,
        Instruction{ .ret = param1 },
        types.I32,
    );

    var cfg = try ControlFlowGraph.fromFunction(allocator, &func);
    defer cfg.deinit(allocator);

    const node1 = cfg.get(block1).?;
    try std.testing.expectEqual(@as(usize, 0), node1.preds.inner.entries.len);
    try std.testing.expectEqual(@as(usize, 1), node1.succs.inner.entries.len);
    try std.testing.expect(node1.succs.contains(block2));

    const node2 = cfg.get(block2).?;
    try std.testing.expectEqual(@as(usize, 1), node2.preds.inner.entries.len);
    try std.testing.expectEqual(@as(usize, 0), node2.succs.inner.entries.len);
    try std.testing.expect(node2.preds.contains(block1));
}
