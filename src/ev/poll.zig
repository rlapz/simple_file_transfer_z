const std = @import("std");
const Connection = std.net.StreamServer.Connection;

const config = @import("../config.zig");
const server = @import("../server.zig");
const Stack = @import("../Stack.zig");
const util = @import("../util.zig");

const Poll = struct {
    _server: *server.Server,
    fds: []std.os.pollfd,
    indexer: []u16,
    clients: []server.Client,
    counter: u16,
    slots: Stack,

    const This = @This();

    fn init(_server: *server.Server) !This {
        const allocator = &_server.allocator;

        var fds = try allocator.alloc(std.os.pollfd, config.max_clients + 1);
        errdefer allocator.free(fds);

        fds[0].fd = _server.stream.sockfd.?;
        fds[0].events = std.os.POLL.IN | std.os.POLL.PRI;

        var clients = try allocator.alloc(server.Client, config.max_clients);
        errdefer allocator.free(clients);

        var indexer = try allocator.alloc(u16, config.max_clients);
        errdefer allocator.free(indexer);

        var slots = try Stack.init(allocator.*, config.max_clients);
        errdefer slots.deinit();

        var i = @intCast(u16, slots.getSize());
        while (i != 0) : (i -= 1) {
            try slots.push(i - 1);
        }

        return This{
            ._server = _server,
            .fds = fds,
            .clients = clients,
            .indexer = indexer,
            .counter = 1,
            .slots = slots,
        };
    }

    fn deinit(this: *This) void {
        // Close all on-going clients
        var i: u16 = 1;
        while (i < this.counter) : (i += 1) {
            const client = &this.clients[this.indexer[i - 1]];

            std.log.debug("Closing client[{}]: \"{}\": {}", .{
                i - 1,
                client.connection.address,
                client.getConnectionFd(),
            });

            client.unset();
        }

        const allocator = &this._server.allocator;
        allocator.free(this.fds);
        allocator.free(this.clients);
        allocator.free(this.indexer);

        this.slots.deinit();
    }

    inline fn getClient(this: *This, index: u16) *server.Client {
        return &this.clients[this.indexer[index - 1]];
    }

    fn clientRemove(this: *This, index: u16, counter: *u16) u16 {
        const slot_curr = this.indexer[index - 1];
        const client = &this.clients[slot_curr];

        this.slots.push(slot_curr) catch |err| {
            std.log.err("Failed to remove client on socket {}: {s}", .{
                client.connection.stream.handle,
                @errorName(err),
            });
            return index;
        };

        const _counter = counter.*;
        this.indexer[index - 1] = this.indexer[_counter - 2];
        this.fds[index] = this.fds[_counter - 1];

        client.unset();

        std.log.debug("Client [{}]: \"{}\": {}: has been closed", .{
            slot_curr,
            client.connection.address,
            client.getConnectionFd(),
        });

        counter.* = _counter - 1;
        this.counter = _counter - 1;

        return (index - 1);
    }

    fn clientAdd(this: *This) !void {
        const conn = this._server.stream.accept() catch |err| {
            std.log.err("Failed to accept a new client", .{});
            return err;
        };

        std.log.debug("New connection from \"{}\" on socket {}", .{
            conn.address,
            conn.stream.handle,
        });

        const slot = this.slots.pop() catch |err| {
            std.log.err("Cannot add a new client: the slot is full", .{});
            conn.stream.close();
            return err;
        };

        const counter = this.counter;
        this.indexer[counter - 1] = slot;

        this.clients[slot].set(conn);

        this.fds[counter].fd = conn.stream.handle;
        this.fds[counter].events = std.os.POLL.IN;
        this.counter = counter + 1;

        std.log.debug("A new client added at {}", .{counter - 1});
    }

    fn clientHandle(this: *This, index: u16, counter: *u16) !u16 {
        const client = this.getClient(index);

        switch (client.status) {
            .wait_file => try client.recvFile(),
            .wait_prop => try client.recvFileProp(),
            .wait_prep => try client.prepFile(),
            .done, .err => return this.clientRemove(index, counter),
        }

        return index;
    }

    fn handleEvents(this: *This) void {
        var iter: u16 = 0;
        var counter = this.counter;
        const fds = this.fds;

        while (iter < counter) : (iter += 1) {
            if (fds[iter].revents != std.os.POLL.IN)
                continue;

            // listener always at 0th index
            if (iter == 0) {
                this.clientAdd() catch |err| {
                    std.log.err("clientAdd: {s}", .{@errorName(err)});
                };
                continue;
            }

            // Update `iter` and `counter` value if any closed client
            iter = this.clientHandle(iter, &counter) catch |err| {
                const client = this.getClient(iter);

                std.log.err("Client [{}]: \"{}\": {}: {s}", .{
                    iter - 1,
                    client.connection.address,
                    client.getConnectionFd(),
                    @errorName(err),
                });

                continue;
            };
        }
    }

    fn loop(this: *This) !void {
        const srv = this._server;
        while (!srv.is_interrupted) {
            const fds = this.fds[0..this.counter];
            if (try std.os.poll(fds, config.poll_timeout) == 0)
                continue;

            this.handleEvents();
        }
    }
};

pub fn run(srv: *server.Server) !void {
    std.log.debug("POLL", .{});
    std.log.debug("Poll size: {}", .{@sizeOf(Poll)});

    var poll = try Poll.init(srv);
    defer poll.deinit();

    try poll.loop();
}

test "poll" {}
