const std = @import("std");

pub fn PooledVec(comptime T: type) type {
    return struct {
        index: u32,

        pub fn get(self: @This(), vec_pool: *ListPool(T), index: u32) T {
            // return optional?
            std.debug.assert(index < vec_pool.getLength(self.index));

            return self.getUnchecked(vec_pool, index);
        }

        pub fn getSlice(self: @This(), vec_pool: *ListPool(T)) []T {
            return vec_pool.get(self.index).?;
        }
    };
}

pub fn ListPool(comptime T: type) type {
    return struct {
        // const Pool = std.heap.MemoryPool([]T);

        // pool: Pool,
        // ptrs: std.ArrayList(*[]T),

        pub fn alloc(self: *@This(), size: usize) !PooledVec(T) {
            _ = self;
            _ = size;
        }

        pub fn get(self: *@This(), index: u32) ?[]T {
            if (index > self.ptrs.items.len) {
                return null;
            }

            return self.ptrs.items[index];
        }
    };
}
