const std = @import("std");

pub fn IndexedMap(comptime K: type, comptime T: type) type {
    return struct {
        values: Map = .{},

        const Map = std.AutoArrayHashMapUnmanaged(K, T);

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.values.deinit(allocator);
        }

        pub fn getPtr(self: @This(), key: K) ?*T {
            return self.values.getPtr(key);
        }

        pub fn get(self: @This(), key: K) ?T {
            return self.values.get(key);
        }

        pub fn put(self: *@This(), allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!K {
            const k: K = @intCast(self.values.entries.len);
            try self.values.put(allocator, k, value);

            return k;
        }

        pub fn iterator(self: *const @This()) Map.Iterator {
            return self.values.iterator();
        }
    };
}
