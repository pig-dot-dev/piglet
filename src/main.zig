const std = @import("std");
const cli = @import("zig-cli");

const Display = @import("display/Display.zig");
const Frame = @import("display/Frame.zig");
const Mouse = @import("input/mouse.zig").Mouse;
const Keyboard = @import("input/Keyboard.zig").Keyboard;
const Computer = @import("Computer.zig");

const getConfig = @import("config.zig").getConfig;
const server = @import("server.zig");
const tunnel = @import("tunnel.zig");
const stream = @import("stream.zig");
const overlay = @import("overlay.zig");

// Define a configuration structure with default values.
var cli_config = struct {
    local_port: u16 = 3000,
    draw_cursor: bool = true,
    control_host: []const u8 = "piglet.pig.dev",
    secret: []const u8 = undefined,
    do_stream: bool = false, // Experimental
    stream_fps: f64 = 20.0,
    stream_bitrate: u32 = 2_500_000,
}{};

pub fn main() !void {
    var r = try cli.AppRunner.init(std.heap.page_allocator);

    const app = cli.App{
        .command = cli.Command{
            .name = "piglet",
            .description = cli.Description{
                .one_line = "Piglet - A computer automation driver for Windows",
            },
            .target = cli.CommandTarget{
                .subcommands = &.{
                    cli.Command{
                        .name = "start",
                        .description = cli.Description{
                            .one_line = "Start a local Piglet server",
                        },
                        .options = &.{
                            .{
                                .long_name = "port",
                                .short_alias = 'p',
                                .help = "Port to bind local server to",
                                .value_ref = r.mkRef(&cli_config.local_port),
                            },
                            .{
                                .long_name = "cursor-overlay",
                                .help = "Enable cursor overlay",
                                .value_ref = r.mkRef(&cli_config.draw_cursor),
                            },
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{
                                .exec = run_local_server,
                            },
                        },
                    },
                    cli.Command{
                        .name = "join",
                        .description = cli.Description{
                            .one_line = "Join the Piglet to a Pig control plane",
                        },
                        .options = &.{
                            .{
                                .long_name = "host",
                                .short_alias = 'h',
                                .help = "Control plane IP/hostname to connect to",
                                .value_ref = r.mkRef(&cli_config.control_host),
                            },
                            .{
                                .long_name = "secret",
                                .help = "API Key to authenticate with the control plane",
                                .required = true,
                                .value_ref = r.mkRef(&cli_config.secret),
                            },
                            .{
                                .long_name = "port",
                                .short_alias = 'p',
                                .help = "Port to bind local server to",
                                .value_ref = r.mkRef(&cli_config.local_port),
                            },
                            .{
                                .long_name = "cursor-overlay",
                                .help = "Enable cursor overlay",
                                .value_ref = r.mkRef(&cli_config.draw_cursor),
                            },
                            .{
                                .long_name = "stream",
                                .help = "Enable screen streaming",
                                .value_ref = r.mkRef(&cli_config.do_stream),
                            },
                            .{
                                .long_name = "stream-fps",
                                .help = "FPS to stream at",
                                .value_ref = r.mkRef(&cli_config.stream_fps),
                            },
                            .{
                                .long_name = "stream-bitrate",
                                .help = "Bitrate to stream at",
                                .value_ref = r.mkRef(&cli_config.stream_bitrate),
                            },
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{
                                .exec = run_worker_server,
                            },
                        },
                    },
                },
            },
        },
        .version = "0.0.7",
        .help_config = .{ .color_usage = .always },
    };
    return r.run(&app);
}

fn run_local_server() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (GPA.deinit() != .ok) std.debug.print("memory leak detected\n", .{});
    const allocator = GPA.allocator();

    // Load machine config (persisted as config.json)
    var config = try getConfig(allocator);
    defer config.deinit(allocator);

    var computer = try Computer.init(allocator);
    defer computer.deinit();

    var overlay_thread: ?std.Thread = null;
    if (cli_config.draw_cursor) {
        overlay_thread = try std.Thread.spawn(
            .{},
            overlay.startOverlay,
            .{allocator},
        );
    }
    defer if (overlay_thread) |ot| ot.join();

    try server.run(allocator, &computer, cli_config.local_port);
}

fn run_worker_server() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (GPA.deinit() != .ok) std.debug.print("memory leak detected\n", .{});
    const allocator = GPA.allocator();

    // Load machine config (persisted as config.json)
    var config = try getConfig(allocator);
    defer config.deinit(allocator);

    var computer = try Computer.init(allocator);
    defer computer.deinit();

    var tunnel_thread = try std.Thread.spawn(
        .{},
        tunnel.startControlTunnel,
        .{
            allocator, config, .{
                .control_host = cli_config.control_host,
                .bearer_token = cli_config.secret,
                .target_port = cli_config.local_port,
            },
        },
    );
    defer tunnel_thread.join();

    var stream_thread: ?std.Thread = null;
    if (cli_config.do_stream) {
        stream_thread = try std.Thread.spawn(
            .{},
            stream.startStream,
            .{ allocator, config, .{
                .display = &computer.display,
                .control_host = cli_config.control_host,
                .bitrate = cli_config.stream_bitrate,
                .fps = cli_config.stream_fps,
            } },
        );
    }
    defer if (stream_thread) |st| st.join();

    var overlay_thread: ?std.Thread = null;
    if (cli_config.draw_cursor) {
        overlay_thread = try std.Thread.spawn(
            .{},
            overlay.startOverlay,
            .{allocator},
        );
    }
    defer if (overlay_thread) |ot| ot.join();

    try server.run(allocator, &computer, cli_config.local_port);
}
