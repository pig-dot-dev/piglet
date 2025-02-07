const std = @import("std");
const win = std.os.windows;
const Display = @import("display/Display.zig");
const Frame = @import("display/Frame.zig");
const Mouse = @import("input/mouse.zig").Mouse;
const Keyboard = @import("input/Keyboard.zig").Keyboard;
const server = @import("server.zig");
const tunnel = @import("tunnel.zig");

const Computer = @import("Computer.zig");

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Default values
    var pig_host: ?[]const u8 = null;
    var pig_port: u16 = 443;
    var target_port: u16 = 3000;

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--control-host") and i + 1 < args.len) {
            pig_host = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--control-port") and i + 1 < args.len) {
            pig_port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            target_port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 1;
        }
    }

    var computer = try Computer.init(allocator);
    defer computer.deinit();

    // Subscribe upstream if host specified
    var tunnel_thread: std.Thread = undefined;
    if (pig_host) |ph| {
        tunnel_thread = try std.Thread.spawn(.{}, tunnel.startControlTunnel, .{
            allocator,
            ph,
            "/ws",
            pig_port,
            target_port,
        });
    }
    defer tunnel_thread.join();

    try server.Run(allocator, &computer, target_port);
}
