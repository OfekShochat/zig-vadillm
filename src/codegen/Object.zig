const std = @import("std");

const Self = @This();

pub const Linkage = enum {
    weak,
    strong,
    undefined,
};

const Symbol = struct {
    offset: usize,
    linkage: Linkage,
};

const SymbolTable = struct {
    symtab: std.ArrayList(Symbol),
    strtab: std.ArrayList(u8),

    pub fn deinit(self: *SymbolTable) void {
        self.buffer.deinit();
    }

    pub fn add(self: *SymbolTable, symbol: Symbol, name: []const u8) !void {
        try self.symtab.append(symbol);

        try self.strtab.ensureUnusedCapacity(name.len + 1);
        try self.strtab.appendSlice(name);
        try self.strtab.append(0);
    }
};

context: *anyopaque,
symtab: SymbolTable,
code_buffer: std.io.AnyWriter,
const_buffer: std.io.AnyWriter,

pub fn registerTextSymbol(self: *Self, name: []const u8, linkage: Linkage) !void {
    try self.symtab.add(
        Symbol{ .linkage = linkage, .offset = self.code_buffer.offset },
        name,
    );
}

pub fn registerConstantSymbol(self: *Self, name: []const u8, linkage: Linkage, data: []const u8) !void {
    try self.symtab.add(
        Symbol{ .linkage = linkage, .offset = self.const_buffer.offset },
        name,
    );

    try self.const_buffer.writeAll(data);
}

pub fn deinit(self: *Self) void {
    self.symtab.deinit();
    self.code_buffer.deinit();
    self.const_buffer.deinit();
}
