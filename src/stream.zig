const std = @import("std");
const Config = @import("config.zig").Config;
const EncoderConfig = @import("stream/EncoderConfig.zig");
const c = @import("display/c.zig").c;
const Display = @import("display/Display.zig");
const H264Encoder = @import("stream/H264Encoder.zig");
const RTMPOutput = @import("stream/RTMPOutput.zig");

pub const StreamOptions = struct {
    control_host: []const u8,
    display: *Display,
    fps: f64 = 30.0,
    bitrate: u32 = 2_500_000,
};

pub fn startStream(allocator: std.mem.Allocator, config: Config, options: StreamOptions) !void {
    const url = try std.fmt.allocPrintZ(
        allocator,
        "rtmps://{s}:1935/live/{s}",
        .{
            options.control_host,
            config.fingerprint,
        },
    );
    defer allocator.free(url);

    var display = options.display;

    const min_sleep_ns: u64 = 1;
    const max_sleep_ns: u64 = 16 * std.time.ns_per_s;
    var sleep_ns: u64 = min_sleep_ns;

    retry: while (true) : ({
        // Continue block; runs between retries
        std.debug.print("Retrying stream connection\n", .{});
        std.time.sleep(sleep_ns);
        sleep_ns = @min(sleep_ns * 2, max_sleep_ns);
    }) {

        // Initialize encoder and output
        var encoder = H264Encoder.init(
            @intCast(display.width()),
            @intCast(display.height()),
            .{
                .fps = options.fps,
                .bitrate = options.bitrate,
            },
        ) catch |err| {
            std.debug.print("Error initializing encoder: {s}\n", .{@errorName(err)});
            continue;
        };
        errdefer encoder.deinit();

        var output = RTMPOutput.init(url, encoder.codec_ctx) catch |err| {
            std.debug.print("Error initializing output: {s}\n", .{@errorName(err)});
            continue;
        };
        defer output.deinit();

        // Initialize frame rate control
        var timer = try std.time.Timer.start();
        const frame_duration_ns: u64 = @intFromFloat(1_000_000_000.0 / options.fps);

        // Stream loop
        while (true) {
            // Get raw frame from display
            var frame = display.capture.getFrame() catch |err| {
                std.debug.print("Error getting frame: {s}\n", .{@errorName(err)});
                continue :retry;
            };
            defer frame.deinit();

            // Encode to H.264
            var packet = encoder.encode(frame) catch |err| {
                std.debug.print("Error encoding frame: {s}\n", .{@errorName(err)});
                continue :retry;
            };
            defer c.av_packet_free(&packet);

            // Send to RTMP server
            try output.write(packet);

            // Maintain frame rate
            const elapsed = timer.read();
            if (elapsed < frame_duration_ns) {
                std.time.sleep(frame_duration_ns - elapsed);
            }
            timer.reset(); // Reset after sleeping
        }
    }
    return error.ConnectError;
}
