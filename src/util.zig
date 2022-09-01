const std = @import("std");

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;

    const prefix = switch (level) {
        .err => "\x1b[01;31m[" ++ comptime level.asText() ++ "]\x1b[00m: ",
        .warn => "\x1b[01;33m[" ++ comptime level.asText() ++ "]\x1b[00m: ",
        .info => "\x1b[01;37m[" ++ comptime level.asText() ++ "]\x1b[00m: ",
        .debug => "\x1b[01;32m[" ++ comptime level.asText() ++ "]\x1b[00m: ",
    };

    const writer = switch (level) {
        .err => std.io.getStdErr().writer(),
        else => std.io.getStdOut().writer(),
    };

    writer.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn setSignal(handler: *const fn (c_int) callconv(.C) void) !void {
    const SIG = std.os.SIG;
    var signal = std.mem.zeroInit(std.os.Sigaction, .{
        .handler = .{ .handler = SIG.IGN },
    });

    try std.os.sigaction(std.os.SIG.PIPE, &signal, null);

    signal.handler = .{ .handler = handler };
    try std.os.sigaction(SIG.TERM, &signal, null);
    try std.os.sigaction(SIG.INT, &signal, null);
    try std.os.sigaction(SIG.HUP, &signal, null);
}

pub inline fn fileCheck(file_name: []const u8) !void {
    if (file_name.len == 0 or file_name.len > 255)
        return error.InvalidFileName;

    if (std.mem.indexOf(u8, file_name, "..") != null)
        return error.InvalidFileName;
}
