const std = @import("std");

const config = @import("config.zig");
const ftransfer = @import("ftransfer.zig");
const util = @import("util.zig");

var g_client: *Client = undefined;

const Client = struct {
    allocator: std.mem.Allocator,
    is_interrupted: bool,
    host: []const u8,
    port: u16,
    stream: std.net.Stream,
    file: struct {
        map: []align(std.mem.page_size) u8,
        size: u64,
        path: []const u8,
    },
    packet: extern union {
        pkt: ftransfer.Packet,
        raw: [@sizeOf(ftransfer.Packet)]u8,
    },

    const This = @This();

    fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        file_path: []const u8,
    ) This {
        return This{
            .allocator = allocator,
            .is_interrupted = false,
            .host = host,
            .port = port,
            .stream = undefined,
            .file = .{
                .map = undefined,
                .size = 0,
                .path = file_path,
            },
            .packet = undefined,
        };
    }

    inline fn sendFile(this: *This) !void {
        std.log.debug("Sending file...", .{});
        try this.stream.writer().writeAll(this.file.map);
    }

    inline fn sendFileProp(this: *This) !void {
        std.log.debug("Sending file properties...", .{});
        try this.stream.writer().writeAll(&this.packet.raw);
    }

    fn setFileProp(this: *This) !void {
        const file = std.fs.cwd().openFile(this.file.path, .{}) catch |err| {
            std.log.err("Cannot open file: {s}", .{this.file.path});
            return err;
        };
        defer file.close();

        const basename = std.fs.path.basename(this.file.path);
        try util.fileCheck(basename);

        const stat = try file.stat();
        const fsize = stat.size;
        this.file.size = fsize;
        this.file.map = try std.os.mmap(
            null,
            fsize,
            std.os.PROT.READ,
            std.os.MAP.PRIVATE,
            file.handle,
            0,
        );

        const pkt = &this.packet.pkt;
        try pkt.setName(basename);
        pkt.setSize(fsize);

        std.log.debug(
            \\
            \\ File properties
            \\ |-> Full path   : {s}
            \\ |-> File name   : {s}
            \\ |-> File size   : {}
            \\ `-> Destination : {s}:{}
        , .{
            this.file.path, basename,  fsize,
            this.host,      this.port,
        });
    }

    fn run(this: *This) !void {
        try util.setSignal(interruptHandler);
        try this.setFileProp();
        defer std.os.munmap(this.file.map);

        this.stream = try std.net.tcpConnectToHost(
            this.allocator,
            this.host,
            this.port,
        );
        defer this.stream.close();

        std.log.debug("Connected to server", .{});

        try this.sendFileProp();
        try this.sendFile();

        std.log.info("Done", .{});
    }
};

fn interruptHandler(sig: c_int) callconv(.C) void {
    std.io.getStdOut().writer().writeAll("\n") catch {};
    std.log.debug("Interrupted!: {}", .{sig});

    std.os.shutdown(g_client.stream.handle, .send) catch |err| {
        std.log.err(
            "Failed to shutdown socket descriptor: {s}",
            .{@errorName(err)},
        );
    };

    g_client.is_interrupted = true;
}

pub fn run(argv: [][*:0]u8) !void {
    if (argv.len != 3)
        return error.InvalidArgument;

    const host = std.mem.span(argv[0]);
    const port = std.fmt.parseUnsigned(u16, std.mem.span(argv[1]), 10) catch {
        std.log.err("Invalid port number", .{});
        return error.InvalidArgument;
    };
    const file_path = std.mem.span(argv[2]);

    var buffer: [config.client_heap_size]u8 align(@alignOf(u64)) = undefined;
    var arena_state = std.heap.FixedBufferAllocator.init(&buffer);
    var client = Client.init(arena_state.allocator(), host, port, file_path);

    g_client = &client;

    client.run() catch |err| {
        if (g_client.is_interrupted)
            return;

        std.log.err("{s}", .{@errorName(err)});
        return err;
    };
}

test "client" {}
