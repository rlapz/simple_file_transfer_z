const std = @import("std");
const builtin = @import("builtin");

const ftransfer = @import("ftransfer.zig");
const config = @import("config.zig");
const client = @import("client.zig");
const server = @import("server.zig");
const util = @import("util.zig");

// Override default log function
pub const log = util.log;

// Override default log level
pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};

const stdout = std.io.getStdOut().writer();

pub fn printHelp(app: []const u8) void {
    stdout.print(
        \\
        \\Usage:
        \\  {s} server [bind_addr] [bind_port]
        \\  {s} client [server_addr] [server_port] [file_name]
        \\
    , .{ app, app }) catch {};
}

pub fn main() u8 {
    if (builtin.os.tag != .linux)
        @compileError("Not supported!");

    std.log.debug("---[DEBUG MODE]---", .{});

    const argv = std.os.argv;
    const arg0 = std.mem.span(argv[0]);

    if (argv.len < 2) {
        printHelp(arg0);
        return 1;
    }

    const arg1 = std.mem.span(argv[1]);
    if (std.mem.eql(u8, arg1, "server")) {
        server.run(argv[2..]) catch |err| {
            if (err == error.InvalidArgument)
                printHelp(arg0);

            return 1;
        };
    } else if (std.mem.eql(u8, arg1, "client")) {
        client.run(argv[2..]) catch |err| {
            if (err == error.InvalidArgument)
                printHelp(arg0);

            return 1;
        };
    } else {
        printHelp(arg0);
        return 1;
    }

    return 0;
}

test "main" {
    _ = @import("ftransfer.zig");
    _ = @import("server.zig");
    _ = @import("client.zig");
    _ = @import("util.zig");
    _ = @import("Stack.zig");

    _ = @import("ev/poll.zig");
    _ = @import("ev/epoll.zig");
    _ = @import("ev/uring.zig");
}
