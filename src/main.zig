const std = @import("std");
const types = @import("types.zig");
const Type = @import("types.zig").Type;
const mem = std.mem;

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

pub const ValueRefList = std.ArrayListUnmanaged(ValueRef);

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

pub const FunctionDecl = struct {
    name: []const u8,
    signature: Signature,
};

// var layout = Layout{
//     .nodes = std.AutoHashMap(BlockRef, BlockNode).init(allocator),
// };
//
// var curr_block: BlockRef = 0;
//
// for (func.insts.items, 0..) |inst, inst_ref| {
//     switch (inst) {
//         .brif => |brif| {
//             try layout.addEdge(curr_block, brif.cond_true, @intCast(inst_ref), allocator);
//             try layout.addEdge(curr_block, brif.cond_false, @intCast(inst_ref), allocator);
//         },
//         .jump => |jump| try layout.addEdge(curr_block, jump.block, @intCast(inst_ref), allocator),
//         else => continue,
//     }
//
//     curr_block += 1;
// }

pub const BlockNode = struct {
    // preds: std.ArrayListUnmanaged(BlockRef) = .{},
    // succs: std.ArrayListUnmanaged(BlockRef) = .{},
    start: InstRef = 0,
    end: InstRef = 0,
};

// um this shouldn't be a cfg, only start/end
// pub const Layout = struct {
//     nodes: std.ArrayListUnmanaged(BlockNode),

//     pub fn fromFunction(func: *const Function, allocator: std.mem.Allocator) !Layout {
//         var layout = Layout{ .nodes = std.ArrayListUnmanaged(BlockNode){} };

//         var curr_block = BlockNode{};

//         for (func.insts.items, 0..) |inst, inst_ref| {
//             switch (inst) {
//                 .brif, .jump => {
//                     curr_block.end = @intCast(inst_ref);
//                     try layout.nodes.append(allocator, curr_block);
//                     curr_block = BlockNode{
//                         .start = @intCast(inst_ref + 1),
//                         .end = @intCast(inst_ref + 1),
//                     };
//                 },
//                 else => {},
//             }
//         }

//         return layout;
//     }

//     pub fn entry(self: Layout) !*const BlockNode {
//         try &self.nodes.get(0);
//     }

//     fn addEdge(self: *Layout, from: BlockRef, to: BlockRef, curr_inst: InstRef, allocator: std.mem.Allocator) !void {
//         const default_blocknode = BlockNode{ .end = curr_inst };

//         var cfg_entry = try self.nodes.getOrPutValue(from, default_blocknode);
//         try cfg_entry.value_ptr.succs.append(allocator, to);

//         cfg_entry = try self.nodes.getOrPutValue(to, default_blocknode);
//         try cfg_entry.value_ptr.preds.append(allocator, from);
//     }
// };

// const ValueMap = std.AutoHashMap(ValueRef, Value);

pub const FunctionBuilder = struct {
    func: Function,
    allocator: std.mem.Allocator,
    blocks: std.ArrayListUnmanaged(Block) = .{},
    value_counter: u32 = 0,

    pub fn init(
        name: []const u8,
        signature: Signature,
        allocator: std.mem.Allocator,
    ) FunctionBuilder {
        return FunctionBuilder{
            .func = Function.init(name, signature),
            .allocator = allocator,
        };
    }

    pub fn build(self: *FunctionBuilder) !Function {
        return self.func;
    }
};

pub const Function = struct {
    name: []const u8,
    signature: Signature,
    blocks: std.AutoHashMapUnmanaged(BlockRef, Block) = .{},
    block_counter: BlockRef = 0,

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
            try kv.value_ptr.formata(kv.key_ptr.*, writer);
        }
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
        var block = self.blocks.getPtr(block_ref);
        std.debug.assert(block != null);

        return block.?.appendInst(allocator, inst, ty);
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

    const ValueMap = std.AutoHashMapUnmanaged(ValueRef, Value);

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

    pub fn iterator(self: ValuePool) ValueMap.Iterator {
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

    pub fn formata(self: *const Block, ref: BlockRef, writer: anytype) !void {
        try writer.print("block{}(", .{ref});
        for (self.params.items, 0..) |param_ref, i| {
            try writer.print("{}", .{self.values.get(param_ref).?.ty});

            if (i < self.params.items.len - 1) {
                try writer.writeAll(", ");
            }
        }

        try writer.writeAll("):\n");

        // try writer.print("die {?}", .{ self.values.get(3)});

        var iter = self.values.iterator();
        while (iter.next()) |kv| {
            try writer.print("{*} {}", .{ kv.key_ptr, kv.value_ptr.data });
            try writer.print("v{} = {} {}", .{ kv.key_ptr.*, kv.value_ptr.ty, kv.value_ptr.data });
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
    std.log.info("{any}", .{func});
    std.log.info("a", .{});
    const p1 = try func.appendBlockParam(alloc, b, types.I32);
    std.log.info("{any}", .{func});
    std.log.info("a", .{});
    const p2 = try func.appendBlockParam(alloc, b, types.I32);

    const val = try func.appendInst(
        alloc,
        b,
        Instruction{ .add = .{ .lhs = p1, .rhs = p2 } },
        types.I32,
    );
    std.log.info("{any}", .{func});
    std.log.info("a", .{});

    const ret = try func.appendInst(
        alloc,
        b,
        Instruction{ .ret = val },
        types.I32,
    );

    std.log.info("{any}", .{func.blocks.get(0).?.insts.items});
    std.log.info("{any}", .{func.blocks.get(0).?.values.get(ret).?.data});
    std.log.info("{any}", .{func});
    // var block = Block{.params = alloc.alloc(Type, 1){types.I32}};
    // const a = try block.appendInst(Instruction{ .add = .{ .lhs = 0, .rhs = 1 } }, types.I32);
    // var block1 = try func.append_block();
    // _ = try func.append_inst(Instruction{ .jump = .{ .block = block1 } }, types.VOID);
    // std.log.info("{}", .{@sizeOf(Instruction)});
}

test "wtf" {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // var alloc = gpa.allocator();
    var alloc = std.testing.allocator;

    var func = Function.init("add", Signature{
        .ret = types.I32,
        .args = .{},
    });

    defer func.deinit(alloc);


    try func.appendParam(alloc, types.I32);

    const b = try func.appendBlock(alloc);
    std.log.info("{any}", .{func});
    std.log.info("a", .{});
    const p1 = try func.appendBlockParam(alloc, b, types.I32);
    std.log.info("{any}", .{func});
    std.log.info("a", .{});
    const p2 = try func.appendBlockParam(alloc, b, types.I32);

    const val = try func.appendInst(
        alloc,
        b,
        Instruction{ .add = .{ .lhs = p1, .rhs = p2 } },
        types.I32,
    );
    std.log.info("{any}", .{func});
    std.log.info("a", .{});

    _ = try func.appendInst(
        alloc,
        b,
        Instruction{ .ret = val },
        types.I32,
    );

    std.log.err("{any}", .{func});
}
