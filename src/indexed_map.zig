const std = @import("std");

pub fn IndexedMap(comptime K: type, comptime T: type) type {
    return struct {
        values: Map = .{},
        counter: K = 0,

        const Map = std.AutoArrayHashMapUnmanaged(K, T);

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.values.deinit(allocator);
        }

        pub fn get(self: @This(), key: K) ?*T {
            return self.values.getPtr(key);
        }

        pub fn put(self: *@This(), allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!K {
            defer self.counter += 1;
            try self.values.put(allocator, self.counter, value);

            return self.counter;
        }

        pub fn iterator(self: *const @This()) Map.Iterator {
            return self.values.iterator();
        }
    };
}
