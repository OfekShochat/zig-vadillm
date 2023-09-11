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

fn sizeFor(size_class: u5) u32 {
    return @as(u32, 4) << size_class;
}

pub fn ListPool(comptime T: type) type {
    return struct {
        comptime {
            if (@sizeOf(T) < @sizeOf(u32)) {
                @compileError("`@sizeOf(T)` has to be bigger than `@sizeOf(u32)` to fit the length inside it.");
            }
        }

        data: std.ArrayList(T),
        free: std.ArrayList(u32),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .data = std.ArrayList(T).init(allocator),
                .free = std.ArrayList(u32).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.data.deinit();
            self.free.deinit();
        }

        pub fn alloc(self: *@This(), size_class: u4) !u32 {
            if (size_class >= self.free.items.len or self.free.items[size_class] == 0) {
                const curr_len = self.data.items.len;
                try self.data.resize(curr_len + sizeFor(size_class));

                const length: *u32 = @ptrCast(&self.data.items[curr_len]);
                length.* = sizeFor(size_class);

                return @intCast(curr_len);
            }

            // free list is a singly linked list of the free blocks,
            // set the free chunks list head to the next free chunk.
            const head = self.free.items[size_class];

            const next: *u32 = @ptrCast(&self.data.items[head]);
            self.free.items[size_class] = next.*;

            return head - 1;
        }

        // offset is the offset with the length
        pub fn dealloc(self: *@This(), offset: u32) !void {
            const length: *u32 = @ptrCast(&self.data.items[offset]);
            const size_class = @ctz(length.*);
            length.* = 0;

            if (self.free.items.len <= size_class) {
                try self.free.resize(size_class + 1);
            }

            // prepend the head into the free chunks list
            var next: *u32 = @ptrCast(&self.data.items[offset + 1]);
            next.* = self.free.items[size_class];
            self.free.items[size_class] = offset + 1;
        }

        pub fn get(self: *@This(), offset: u32) ?[]T {
            if (offset >= self.data.items.len) {
                return null;
            }

            const length: *u32 = @ptrCast(&self.data.items[offset]);
            std.log.err("{} {}", .{ length.*, offset });
            return self.data.items[offset + 1 ..][0 .. length.* - 1];
        }
    };
}

test "ListPool" {
    const Yhali = packed struct {
        is_good: bool,
        die: u32,
    };

    var list_pool = ListPool(Yhali).init(std.testing.allocator);
    const index = try list_pool.alloc(3);
    try list_pool.dealloc(3);

    const index2 = try list_pool.alloc(2);

    defer list_pool.deinit();

    std.log.err("{}", .{index});
    std.log.err("{}", .{index2});
    std.log.err("{}", .{list_pool});
    std.log.err("{}", .{list_pool.data.items.len});
}
