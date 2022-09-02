const std = @import("std");

allocator: std.mem.Allocator,
index: u16,
buffer: []u16,

const This = @This();

pub fn init(allocator: std.mem.Allocator, size: usize) !This {
    return This{
        .allocator = allocator,
        .index = 0,
        .buffer = try allocator.alloc(u16, size),
    };
}

pub fn deinit(this: *This) void {
    this.allocator.free(this.buffer);
    this.index = 0;
}

pub fn push(this: *This, data: u16) !void {
    const index = this.index;

    if (index == this.buffer.len)
        return error.NoSpaceLeft;

    this.buffer[index] = data;
    this.index = index + 1;
}

pub fn pop(this: *This) !u16 {
    var index = this.index;

    if (index == 0)
        return error.StackEmpty;

    index -= 1;
    this.index = index;

    return this.buffer[index];
}

pub inline fn getSize(this: *This) usize {
    return this.buffer.len;
}

test "stack" {}
