const std = @import("std");
const ir = @import("ir.zig");

const Type = @import("types.zig").Type;
const Index = ir.Index;
const Constant = ir.Constant;
const ValuePool = ir.ValuePool;
const IndexedMap = @import("indexed_map.zig").IndexedMap;
const Instruction = @import("instructions.zig").Instruction;

pub const Signature = struct {
    ret: Type,
    args: std.ArrayListUnmanaged(Type),

    pub fn deinit(self: *Signature, allocator: std.mem.Allocator) void {
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

pub const Function = struct {
    signature: Signature,
    allocator: std.mem.Allocator,
    blocks: std.AutoArrayHashMapUnmanaged(Index, Block) = .{},
    values: ValuePool = .{},
    entry_ref: Index = 0,
    block_counter: Index = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        signature: Signature,
    ) Function {
        return Function{
            .signature = signature,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.blocks.entries.items(.value)) |*b| {
            b.deinit(allocator);
        }
        self.blocks.deinit(allocator);
        self.signature.deinit(allocator);
        self.values.deinit(allocator);
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
            _ = kv;
            // try kv.value_ptr.print(&self.values, kv.key_ptr.*, writer);
        }
    }

    pub fn entryBlock(self: Function) Index {
        return self.entry_ref;
    }

    pub fn appendBlock(self: *Function, allocator: std.mem.Allocator) std.mem.Allocator.Error!Index {
        defer self.block_counter += 1;
        try self.blocks.put(allocator, self.block_counter, Block{ .ref = self.block_counter });

        return self.block_counter;
    }

    pub fn addValue(self: *Function, value: Value) !Index {
        return self.values.put(value);
    }

    pub fn getValue(self: *Function, value_ref: Index) !?*Value {
        return self.values.getPtr(value_ref);
    }

    pub fn addConst(self: *Function, allocator: std.mem.Allocator, c: Constant, ty: Type) !Index {
        return self.values.put(allocator, Value.init(ValueData{ .constant = c }, ty));
    }

    pub fn appendInst(
        self: *Function,
        allocator: std.mem.Allocator,
        block_ref: Index,
        inst: Instruction,
        ty: Type,
    ) std.mem.Allocator.Error!Index {
        if (self.blocks.getPtr(block_ref)) |block| {
            return block.appendInst(allocator, &self.values, inst, ty);
        }

        // should this actually be unreachable?
        unreachable;
    }

    pub fn appendBlockParam(self: *Function, allocator: std.mem.Allocator, block_ref: Index, ty: Type) std.mem.Allocator.Error!Index {
        if (self.blocks.getPtr(block_ref)) |block| {
            return block.appendParam(allocator, &self.values, ty);
        }

        unreachable;
    }

    pub fn appendParam(self: *Function, allocator: std.mem.Allocator, ty: Type) std.mem.Allocator.Error!void {
        return self.signature.args.append(allocator, ty);
    }
};

pub const Block = struct {
    ref: Index,
    params: std.ArrayListUnmanaged(Index) = .{},
    insts: std.ArrayListUnmanaged(Instruction) = .{},

    pub fn deinit(self: *Block, allocator: std.mem.Allocator) void {
        self.insts.deinit(allocator);
        self.params.deinit(allocator);
    }

    pub fn appendParam(self: *Block, allocator: std.mem.Allocator, value_pool: *ValuePool, ty: Type) std.mem.Allocator.Error!Index {
        const param_ref = try value_pool.put(allocator, Value.init(ValueData{
            .param = .{ .block = self.ref, .idx = self.params.items.len },
        }, ty));

        try self.params.append(allocator, param_ref);

        return param_ref;
    }

    pub fn appendInst(self: *Block, allocator: std.mem.Allocator, value_pool: *ValuePool, inst: Instruction, ty: Type) std.mem.Allocator.Error!Index {
        return self.insertInst(allocator, value_pool, @intCast(self.insts.items.len), inst, ty);
    }

    pub fn insertInstBeforeTerm(
        self: *Block,
        allocator: std.mem.Allocator,
        value_pool: *ValuePool,
        inst: Instruction,
        ty: Type,
    ) std.mem.Allocator.Error!Index {
        std.debug.assert(self.insts.items.len > 0);

        return self.insertInst(allocator, value_pool, self.insts.items.len - 1, inst, ty);
    }

    pub fn insertInst(
        self: *Block,
        allocator: std.mem.Allocator,
        value_pool: *ValuePool,
        before: Index,
        inst: Instruction,
        ty: Type,
    ) std.mem.Allocator.Error!Index {
        std.debug.assert(before <= self.insts.items.len);

        try self.insts.insert(allocator, before, inst);

        return value_pool.put(
            allocator,
            Value.init(ValueData{ .inst = .{ .block = self.ref, .pos = @intCast(before) } }, ty),
        );
    }

    pub fn getTerminator(self: Block) Instruction {
        return self.insts.getLast();
    }
};

pub const ValueData = union(enum) {
    alias: struct { to: Index },
    param: struct { block: Index, idx: usize },
    global_value: Index,
    constant: Constant,
    inst: struct { block: Index, pos: Index },
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
