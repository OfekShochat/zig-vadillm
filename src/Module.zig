const std = @import("std");

const Signature = @import("function.zig").Signature;
const Function = @import("function.zig").Function;
const ValuePool = @import("common.zig").ValuePool;
const Index = @import("common.zig").Index;
const Constant = @import("common.zig").Constant;

const Module = @This();

pub const GlobalValue = struct {
    name: []const u8,
    initial_value: ?Constant,
};

func_decls: std.StringHashMap(Signature),
func_defs: std.StringHashMap(Function),
global_values: ValuePool(Index, GlobalValue),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !void {
    return Module{
        .funcs = std.StringHashMap(Function).init(allocator),
        .func_decls = std.StringHashMap(Signature).init(allocator),
        .global_values = std.AutoHashMap(Index, GlobalValue).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Module) void {
    self.func_decls.deinit();
    for (self.func_defs.items) |func| {
        func.deinit();
    }
    self.func_defs.deinit();
    self.global_values.deinit();
}

pub fn declareFunction(self: *Module, name: []const u8, signature: Signature) !void {
    return self.func_decls.put(name, signature);
}

pub fn defineFunction(self: *Module, name: []const u8, func: Function) !void {
    return self.func_defs.put(name, func);
}

// pub fn defineGlobalValue(self: *Module, gv: GlobalValue) !void {
//     // return self.global_values.put(, gv);
// }
