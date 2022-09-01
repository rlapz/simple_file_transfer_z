const std = @import("std");

const config = @import("../config.zig");
const server = @import("../server.zig");
const Stack = @import("../Stack.zig");
const util = @import("../util.zig");

const EPOLL = std.os.linux.EPOLL;

const Epoll = struct {
    _server: *server.Server,
    events: []std.os.linux.epoll_event,
    event: std.os.linux.epoll_event,
    fd: i32,
    slots: Stack,

    const This = @This();

    fn init(_server: *server.Server) !This {
        const a = _server.allocator;

        var clients = try a.alloc(server.Client, config.max_clients);
        errdefer a.free(clients);

        var events = try a.alloc(std.os.linux.epoll_event, config.max_clients);
        errdefer a.free(events);

        return This{
            ._server = _server,
            .events = events,
            .event = undefined,
            .fd = undefined,
            .slots = try Stack.init(a, config.max_clients),
        };
    }

    fn deinit(this: *This) void {
        _ = this;
    }

    fn handleEvents(this: *This, events: usize) void {
        _ = this;
        _ = events;
        std.log.debug("well...", .{});
    }

    fn loop(this: *This) !void {
        const srv = this._server;
        const listener = srv.stream.sockfd orelse {
            return error.InvalidArgument;
        };
        this.event.events = EPOLL.IN | EPOLL.PRI;
        this.event.data.fd = listener;
        this.fd = try std.os.epoll_create1(0);
        try std.os.epoll_ctl(this.fd, EPOLL.CTL_ADD, listener, &this.event);

        while (!srv.is_interrupted) {
            const ret = std.os.epoll_wait(
                this.fd,
                this.events,
                config.epoll_timeout,
            );

            if (ret == 0)
                continue;

            this.handleEvents(ret);
        }
    }
};

pub fn run(srv: *server.Server) !void {
    std.log.debug("EPOLL", .{});
    std.log.debug("Epoll size: {}", .{@sizeOf(Epoll)});

    var epoll = try Epoll.init(srv);
    defer epoll.deinit();

    try epoll.loop();
}

test "epoll" {}
