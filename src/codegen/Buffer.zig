const std = @import("std");

const Self = @This();

pub const VTable = struct {
    write: *const fn (*anyopaque, []const u8) anyerror!usize,
    writeByte: *const fn (*anyopaque, u8) anyerror!usize,
    deinit: *const fn (*anyopaque) void,
};

vptr: *anyopaque,
vtable: VTable,
offset: usize = 0,

pub fn deinit(self: *Self) void {
    self.vtable.deinit(self.vptr);
}

pub fn print(self: Self, comptime format: []const u8, args: anytype) !void {
    return std.fmt.format(self, format, args);
}

pub fn write(self: *Self, bytes: []const u8) !usize {
    const written = self.vtable.write(self.vptr, bytes);
    self.offset += written;
    return written;
}

pub fn writeAll(self: *Self, bytes: []const u8) !void {
    var written = 0;
    while (written < bytes.len) {
        written += try self.write(bytes[written..]);
    }
}

pub fn writeByte(self: *Self, byte: u8) !void {
    self.offset += 1;
    return self.vtable.writeByte(self.vptr, byte);
}

pub fn writeStruct(self: *Self, value: anytype) !void {
    return self.writeAll(std.mem.asBytes(&value));
}
