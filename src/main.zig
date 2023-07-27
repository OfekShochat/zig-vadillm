const std = @import("std");
const types = @import("types.zig");
const Type = @import("types.zig").Type;

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

    brif: struct {
        cond: ValueRef,
        cond_true: BlockCall,
        cond_false: BlockCall,
    },

    jump: struct { block: BlockRef },

    call: struct {
        func: FuncRef,
        args: [*]ValueRef,
    },
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
    param: struct { idx: usize, block: BlockRef },
    global_value: struct { name: []const u8, initial_value: ConstantRef },
    constant: ConstantRef,
    inst: InstRef,
};

pub const Signature = struct {
    ret: Type,
    args: std.ArrayListUnmanaged(Type),
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
pub const Layout = struct {
    nodes: std.ArrayListUnmanaged(BlockNode),

    pub fn fromFunction(func: *const Function, allocator: std.mem.Allocator) !Layout {
        var layout = Layout{ .nodes = std.ArrayListUnmanaged(BlockNode){} };

        var curr_block = BlockNode{};

        for (func.insts.items, 0..) |inst, inst_ref| {
            switch (inst) {
                .brif, .jump => {
                    curr_block.end = @intCast(inst_ref);
                    try layout.nodes.append(allocator, curr_block);
                    curr_block = BlockNode{
                        .start = @intCast(inst_ref + 1),
                        .end = @intCast(inst_ref + 1),
                    };
                },
                else => {},
            }
        }

        return layout;
    }

    pub fn entry(self: Layout) !*const BlockNode {
        try &self.nodes.get(0);
    }

    fn addEdge(self: *Layout, from: BlockRef, to: BlockRef, curr_inst: InstRef, allocator: std.mem.Allocator) !void {
        const default_blocknode = BlockNode{ .end = curr_inst };

        var cfg_entry = try self.nodes.getOrPutValue(from, default_blocknode);
        try cfg_entry.value_ptr.succs.append(allocator, to);

        cfg_entry = try self.nodes.getOrPutValue(to, default_blocknode);
        try cfg_entry.value_ptr.preds.append(allocator, from);
    }
};

const ValueMap = std.AutoHashMap(ValueRef, Value);

pub const FunctionBuilder = struct {
    func: Function,
    allocator: std.mem.Allocator,
    blocks: std.ArrayListUnmanaged(std.ArrayListUnmanaged(ValueRef)) = .{},
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

    pub fn insert_inst(self: *FunctionBuilder, before: InstRef, inst: Instruction, ty: Type) !InstRef {
        std.debug.assert(before <= self.func.insts.items.len);

        try self.func.insts.insert(self.allocator, before, inst);

        defer self.value_counter += 1;

        try self.func.values.put(
            self.allocator,
            self.value_counter,
            Value.init(ValueData{ .inst = @intCast(self.func.insts.items.len) }, ty),
        );

        return @intCast(self.value_counter);
    }

    pub fn append_inst(self: *FunctionBuilder, inst: Instruction, ty: Type) !InstRef {
        return self.insert_inst(@intCast(self.func.insts.items.len), inst, ty);
    }

    pub fn insert_inst_after(self: *FunctionBuilder, after: InstRef, inst: Instruction, ty: Type) !InstRef {
        return self.insert_inst(after + 1, inst, ty);
    }

    pub fn append_block(self: *FunctionBuilder) !BlockRef {
        try self.blocks.append(self.allocator, .{});
        return @intCast(self.blocks.items.len - 1);
    }

    pub fn append_block_param(self: *FunctionBuilder, block: BlockRef, ty: Type) !ValueRef {
        const arg_idx = self.blocks.items[block].items.len;

        defer self.value_counter += 1;

        self.func.values.put(
            self.allocator,
            self.value_counter,
            Value.init(ValueData{ .param = .{
                .block = block,
                .idx = arg_idx,
            } }, ty),
        );

        try self.blocks.items[block].append(self.value_counter);
    }

    pub fn build(self: *FunctionBuilder) !Function {
        std.debug.assert(self.blocks.items.len > 0);

        for (self.blocks.items) |*params| {
            try self.func.blocks.append(self.allocator, Block{
                .start = 0,
                .end = 0,
                .params = try params.toOwnedSlice(self.allocator),
            });
        }

        var block_index: BlockRef = 0;

        for (self.func.insts.items, 0..) |inst, inst_ref| {
            switch (inst) {
                .brif, .jump => {
                    self.func.blocks.items[block_index].end = @intCast(inst_ref);

                    block_index += 1;
                    self.func.blocks.items[block_index].start = @intCast(inst_ref);
                },
                else => {},
            }
        }

        return self.func;
    }
};

pub const Function = struct {
    name: []const u8,
    signature: Signature,
    insts: std.ArrayListUnmanaged(Instruction),
    blocks: std.ArrayListUnmanaged(Block),
    values: std.AutoHashMapUnmanaged(ValueRef, Value),
    preamble_end: InstRef = 0,
    counter: u32 = 0,

    pub fn init(
        name: []const u8,
        signature: Signature,
    ) Function {
        return Function{
            .name = name,
            .signature = signature,
            .insts = std.ArrayListUnmanaged(Instruction){},
            .blocks = std.ArrayListUnmanaged(Block){},
            .values = std.AutoHashMapUnmanaged(ValueRef, Value){},
        };
    }
};

pub const Block = struct {
    params: []ValueRef,

    // both are inclusive
    start: InstRef,
    end: InstRef,
};

pub const Value = struct {
    // uses: std.ArrayList(Value),
    data: ValueData,
    ty: Type,

    pub fn init(data: ValueData, ty: Type) Value {
        return Value{
            // .uses = ValueRefList.init(alloc),
            .data = data,
            .ty = ty,
        };
    }

    pub fn deinit(self: Value) void {
        self.uses.deinit();
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

    var func = FunctionBuilder.init("main", Signature{
        .ret = types.I32,
        .args = std.ArrayListUnmanaged(Type){},
    }, alloc);

    var block_sig = try alloc.alloc(types.Type, 1);
    block_sig[0] = types.I32;

    _ = try func.append_block();

    _ = try func.append_inst(Instruction{ .add = .{ .lhs = 0, .rhs = 1 } }, types.I32);
    var block1 = try func.append_block();
    _ = try func.append_inst(Instruction{ .jump = .{ .block = block1 } }, types.VOID);
    std.log.info("{}", .{(try func.build()).blocks});
    std.log.info("{}", .{@sizeOf(Instruction)});
}
