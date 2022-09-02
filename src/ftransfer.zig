const std = @import("std");

pub const Packet = extern struct {
    size: u64,
    name_len: u8,
    name: [0xff]u8,

    const This = @This();

    pub inline fn setSize(this: *This, size: u64) void {
        this.size = std.mem.nativeToBig(u64, size);
    }

    pub inline fn getSize(this: *This) u64 {
        return std.mem.bigToNative(u64, this.size);
    }

    pub fn setName(this: *This, name: []const u8) !void {
        const _len = name.len;
        if (_len > 0xff)
            return error.NameTooLong;

        this.name_len = @intCast(u8, _len);
        std.mem.copy(u8, &this.name, name);
        this.name[_len] = 0;
    }

    pub inline fn getName(this: *This) []const u8 {
        return this.name[0..this.name_len];
    }
};
