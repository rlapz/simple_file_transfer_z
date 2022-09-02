const std = @import("std");
const Connection = std.net.StreamServer.Connection;

const config = @import("config.zig");
const ftransfer = @import("ftransfer.zig");
const util = @import("util.zig");

const ev = switch (config.ev_type) {
    .poll => @import("ev/poll.zig"),
    .epoll => @import("ev/epoll.zig"),
    .uring => @import("ev/uring.zig"),
};

var g_server: *Server = undefined;

pub const Client = struct {
    status: enum(u8) {
        wait_prop, // File properties
        wait_prep, // Prepare
        wait_file, // File IO
        done,
        err,
    },
    file: struct {
        fd: ?std.fs.File,
        name: []const u8,
        size: u64,
    },
    recvd: u64, // received bytes
    connection: Connection,
    packet: extern union {
        pkt: ftransfer.Packet,
        raw: [config.buffer_size]u8,
    },

    const This = @This();

    pub inline fn set(this: *This, conn: Connection) void {
        this.connection = conn;
        this.recvd = 0;
        this.file.fd = null;
        this.status = .wait_prop;
    }

    pub inline fn getConnectionFd(this: *This) std.os.fd_t {
        return this.connection.stream.handle;
    }

    pub fn recvFileProp(this: *This) !void {
        errdefer this.status = .err;

        const buffer_size = @sizeOf(@TypeOf(this.packet.pkt));
        var recvd = this.recvd;

        if (recvd < buffer_size) brk: {
            var buffer = this.packet.raw[recvd..buffer_size];
            const _recvd = try this.connection.stream.read(buffer);
            if (_recvd == 0)
                break :brk;

            recvd += _recvd;
            this.recvd = recvd;

            return;
        }

        if (recvd != buffer_size)
            return error.BrokenFileProperties;

        std.log.debug("File properties size: {}", .{recvd});

        const pkt = &this.packet.pkt;
        const file = &this.file;

        file.name = pkt.getName();
        try util.fileCheck(file.name);

        file.size = pkt.getSize();
        this.recvd = 0;
        this.status = .wait_prep;

        const conn = &this.connection;
        std.log.debug(
            \\
            \\ Client: "{}" on socket: {}
            \\ File:
            \\  Name : {s}
            \\  Size : {}
        ,
            .{
                conn.address, conn.stream.handle,
                file.name,    file.size,
            },
        );
    }

    pub fn prepFile(this: *This) !void {
        errdefer this.status = .err;

        const file = &this.file;
        const path = config.__upload_dir;
        const buffer_len = path.len + @sizeOf(@TypeOf(this.packet.pkt.name));
        var buffer: [buffer_len]u8 = undefined;

        std.mem.copy(u8, &buffer, path);
        std.mem.copy(u8, buffer[path.len..], file.name);

        const target = buffer[0 .. path.len + file.name.len];
        file.fd = try std.fs.cwd().createFile(target, .{ .truncate = true });
        this.status = .wait_file;

        std.log.debug("{s}:{}", .{ target, target.len });
    }

    pub fn recvFile(this: *This) !void {
        errdefer this.status = .err;

        const file = &this.file;
        var crecvd = this.recvd;
        const cfsize = this.file.size;

        if (crecvd < cfsize) blk: {
            const buffer = &this.packet.raw;
            const recvd = try this.connection.stream.read(buffer);
            if (recvd == 0)
                break :blk;

            crecvd += try file.fd.?.write(buffer[0..recvd]);
            this.recvd = crecvd;

            return;
        }

        std.log.debug("File size: {}, received: {}", .{ cfsize, crecvd });

        if (crecvd != cfsize)
            return error.BrokenFile;

        this.status = .done;

        std.log.debug("Done :3", .{});
    }

    pub fn unset(this: *This) void {
        if (this.file.fd) |*fd| {
            fd.sync() catch |err| {
                std.log.err("sync: {s}", .{@errorName(err)});
            };
            fd.close();
            this.file.fd = null;
        }

        this.connection.stream.close();
    }
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    is_interrupted: bool,
    host: []const u8,
    port: u16,
    stream: std.net.StreamServer,

    const This = @This();

    fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) This {
        std.log.info("Initializing...", .{});

        return This{
            .allocator = allocator,
            .is_interrupted = false,
            .host = host,
            .port = port,
            .stream = undefined,
        };
    }

    fn deinit(this: This) void {
        _ = this;
        std.log.info("Server stopped", .{});
    }

    fn setupTcp(this: *This) !void {
        std.log.info("Setup TCP server", .{});

        this.stream = std.net.StreamServer.init(.{
            .reuse_address = true,
            .kernel_backlog = config.kernel_backlog,
        });

        try this.stream.listen(
            try std.net.Address.resolveIp(this.host, this.port),
        );
    }

    fn run(this: *This) !void {
        std.fs.cwd().makeDir(config.__upload_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                std.log.err("Cannot create a new directory: {s}", .{
                    config.__upload_dir,
                });
                return err;
            },
        };

        try util.setSignal(interruptHandler);

        try this.setupTcp();
        defer this.stream.deinit();

        std.log.info(
            \\
            \\ [Server started]
            \\ |-> Address       : {s}
            \\ |-> Port          : {}
            \\ |-> Buffer size   : {}
            \\ |-> Event handler : {s}
            \\ `-> Max clients   : {}
        , .{
            this.host,          this.port,
            config.buffer_size, @tagName(config.ev_type),
            config.max_clients,
        });

        try ev.run(this);
    }
};

fn interruptHandler(sig: c_int) callconv(.C) void {
    std.io.getStdOut().writer().writeAll("\n") catch {};
    std.log.info("Interrupted!: {}", .{sig});

    std.os.shutdown(g_server.stream.sockfd.?, .both) catch |err| {
        std.log.err("Failed to shutdown server socket descriptor: {s}", .{
            @errorName(err),
        });
    };

    g_server.is_interrupted = true;
}

pub fn run(argv: [][*:0]u8) !void {
    if (argv.len != 2)
        return error.InvalidArgument;

    std.log.debug("Server size: {}. Client size: {}", .{
        @sizeOf(Server),
        @sizeOf(Client),
    });

    const host = std.mem.span(argv[0]);
    const port = std.fmt.parseUnsigned(u16, std.mem.span(argv[1]), 10) catch {
        std.log.err("Invalid port number", .{});
        return error.InvalidArgument;
    };

    const allocator = std.heap.page_allocator;
    var server = Server.init(allocator, host, port);
    defer server.deinit();

    g_server = &server;

    server.run() catch |err| {
        if (g_server.is_interrupted)
            return;

        std.log.err("{s}", .{@errorName(err)});
        return err;
    };
}

test "server" {}
