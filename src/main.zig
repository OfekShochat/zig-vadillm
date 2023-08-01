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

pub const BinOp = struct { lhs: ValueRef, rhs: ValueRef };

// possible optimization, use [*] and a u8 len becaues we don't have that many registers
pub const BlockCall = struct {
    block: BlockRef,
    args: []ValueRef,
};

pub const Instruction = union(enum) {
    add: BinOp,
    sub: BinOp,
    mul: BinOp,
    shl: BinOp,
    shr: BinOp,

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

    jump: struct { block: BlockRef },

    ret: ValueRef,
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

pub const Module = struct {
    funcs: std.ArrayList(Function),
    func_decls: std.ArrayList(FunctionDecl),
    constants: std.ArrayList(Constant),
};

pub const Target = struct {};

pub const Constant = []const u8;

pub const ValueData = union(enum) {
    alias: struct { to: ValueRef },
    param: struct { idx: usize },
    global_value: struct { name: []const u8, initial_value: ConstantRef },
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

        pub fn put(self: *@This(), allocator: std.mem.Allocator, val: T) !void {
            return self.inner.put(allocator, val, void{});
        }

        pub fn contains(self: @This(), key: T) bool {
            return self.inner.contains(key);
        }

        pub fn iter(self: @This()) []T {
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
    nodes: std.AutoHashMapUnmanaged(BlockRef, CFGNode) = .{},

    pub fn fromFunction(allocator: std.mem.Allocator, func: *const Function) !ControlFlowGraph {
        var cfg = ControlFlowGraph{};

        var iter = func.blocks.iterator();
        while (iter.next()) |kv| {
            switch (kv.value_ptr.getTerminator()) {
                .brif => |brif| {
                    try cfg.addEdge(allocator, kv.key_ptr.*, brif.cond_true.block);
                    try cfg.addEdge(allocator, kv.key_ptr.*, brif.cond_false.block);
                },
                .jump => |jump| try cfg.addEdge(allocator, kv.key_ptr.*, jump.block),
                else => try cfg.nodes.put(allocator, kv.key_ptr.*, CFGNode{}),
            }
        }

        return cfg;
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
    blocks: std.AutoHashMapUnmanaged(BlockRef, Block) = .{},
    block_counter: BlockRef = 0,
    entry_ref: BlockRef = 0,

    pub fn init(
        name: []const u8,
        signature: Signature,
    ) Function {
        return Function{
            .name = name,
            .signature = signature,
        };
    }

    pub fn deinit(self: *Function, allocator: mem.Allocator) void {
        var iter = self.blocks.valueIterator();
        while (iter.next()) |b| {
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
            try kv.value_ptr.format(kv.key_ptr.*, writer);
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

    pub fn appendInst(
        self: *Function,
        allocator: mem.Allocator,
        block_ref: BlockRef,
        inst: Instruction,
        ty: Type,
    ) mem.Allocator.Error!ValueRef {
        if (self.blocks.getPtr(block_ref)) |block| {
            return block.appendInst(allocator, inst, ty);
        }

        unreachable;
    }

    pub fn appendBlockParam(self: *Function, allocator: mem.Allocator, block_ref: BlockRef, ty: Type) mem.Allocator.Error!ValueRef {
        if (self.blocks.getPtr(block_ref)) |block| {
            return block.appendParam(allocator, ty);
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
    values: ValuePool = .{},

    pub fn deinit(self: *Block, allocator: mem.Allocator) void {
        self.insts.deinit(allocator);
        self.params.deinit(allocator);
        self.values.deinit(allocator);
    }

    pub fn format(self: *const Block, ref: BlockRef, writer: anytype) !void {
        try writer.print("block{}(", .{ref});
        for (self.params.items, 0..) |param_ref, i| {
            try writer.print("{}", .{self.values.get(param_ref).?.ty});

            if (i < self.params.items.len - 1) {
                try writer.writeAll(", ");
            }
        }

        try writer.writeAll("):\n");

        var iter = self.values.iterator();
        while (iter.next()) |kv| {
            try writer.print("v{} = {} {}\n", .{ kv.key_ptr.*, kv.value_ptr.ty, kv.value_ptr.data });
        }
    }

    pub fn appendParam(self: *Block, allocator: mem.Allocator, ty: Type) mem.Allocator.Error!ValueRef {
        const param_ref = try self.values.put(allocator, Value.init(ValueData{
            .param = .{ .idx = self.params.items.len },
        }, ty));

        try self.params.append(allocator, param_ref);

        return param_ref;
    }

    pub fn appendInst(self: *Block, allocator: mem.Allocator, inst: Instruction, ty: Type) mem.Allocator.Error!ValueRef {
        return self.insertInst(allocator, @intCast(self.insts.items.len), inst, ty);
    }

    pub fn insertInstBeforeTerm(
        self: *Block,
        allocator: mem.Allocator,
        inst: Instruction,
        ty: Type,
    ) mem.Allocator.Error!ValueRef {
        std.debug.assert(self.insts.items.len > 0);

        return self.insertInst(allocator, self.insts.items.len - 1, inst, ty);
    }

    pub fn insertInst(
        self: *Block,
        allocator: mem.Allocator,
        before: InstRef,
        inst: Instruction,
        ty: Type,
    ) mem.Allocator.Error!ValueRef {
        std.debug.assert(before <= self.insts.items.len);

        try self.insts.insert(allocator, before, inst);

        return self.values.put(
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

    var func = Function.init("add", Signature{
        .ret = types.I32,
        .args = .{},
    });

    defer func.deinit(alloc);

    try func.appendParam(alloc, types.I32);

    const b = try func.appendBlock(alloc);
    const b2 = try func.appendBlock(alloc);
    _ = try func.appendInst(
        alloc,
        b,
        Instruction{ .jump = .{ .block = b2 } },
        types.I32,
    );

    const p1 = try func.appendBlockParam(alloc, b, types.I32);

    const ret = try func.appendInst(
        alloc,
        b2,
        Instruction{ .ret = p1 },
        types.I32,
    );

    const cfg = try ControlFlowGraph.fromFunction(alloc, &func);
    std.log.info("{any}", .{func.blocks.get(0).?.insts.items});
    std.log.info("{any}", .{func.blocks.get(0).?.values.get(ret).?.data});
    std.log.info("{any}", .{func});
    std.log.info("{any}", .{cfg});

    var domtree = a{};
    try domtree.computePostorder(alloc, &cfg, &func);
    std.log.info("{any}", .{domtree.formatter(&func)});
}
