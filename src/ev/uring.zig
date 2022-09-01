const std = @import("std");

const server = @import("../server.zig");

pub fn run(srv: *server.Server) !void {
    std.log.debug("URING", .{});
    _ = srv;

    @compileError("uring: Not supported!");
}

test "uring" {}
