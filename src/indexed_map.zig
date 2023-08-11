const std = @import("std");

const Index = @import("common.zig").Index;

pub fn IndexedMap(comptime T: type) type {
    return struct {
        values: Map = .{},
        counter: Index = 0,

        const Map = std.AutoArrayHashMapUnmanaged(Index, T);

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.values.deinit(allocator);
        }

        pub fn get(self: @This(), key: Index) ?*T {
            return self.values.getPtr(key);
        }

        pub fn put(self: *@This(), allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!Index {
            defer self.counter += 1;
            try self.values.put(allocator, self.counter, value);

            return self.counter;
        }

        pub fn iterator(self: *const @This()) Map.Iterator {
            return self.values.iterator();
        }
    };
}
