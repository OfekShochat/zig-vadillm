const std = @import("std");

pub fn HashSet(comptime T: type) type {
    return struct {
        inner: std.AutoArrayHashMapUnmanaged(T, void) = .{},

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
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
