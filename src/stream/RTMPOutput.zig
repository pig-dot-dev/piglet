const std = @import("std");
const c = @import("../display/c.zig").c;

pub const RTMPOutput = @This();

/// FFmpeg format context for output
format_ctx: [*c]c.AVFormatContext,
/// Index of the video stream
stream_index: c_int,

pub fn init(url: []const u8, codec_ctx: [*c]c.AVCodecContext) !RTMPOutput {
    // Initialize networking
    if (c.avformat_network_init() < 0) {
        return error.NetworkInitFailed;
    }

    // Allocate format context
    var format_ctx: [*c]c.AVFormatContext = undefined;
    if (c.avformat_alloc_output_context2(
        &format_ctx,
        null,
        "flv", // Explicitly set format to FLV
        url.ptr,
    ) < 0) return error.OutputContextFailed;
    errdefer c.avformat_free_context(format_ctx);

    // Add video stream
    const stream = c.avformat_new_stream(format_ctx, null);
    if (stream == null) return error.StreamFailed;

    // Copy codec parameters
    if (c.avcodec_parameters_from_context(stream.*.codecpar, codec_ctx) < 0) {
        return error.CodecParamsFailed;
    }

    stream.*.time_base = codec_ctx.*.time_base;
    stream.*.avg_frame_rate = codec_ctx.*.framerate;
    stream.*.r_frame_rate = codec_ctx.*.framerate;

    // Use default Options
    var opts: ?*c.AVDictionary = null;
    defer if (opts != null) c.av_dict_free(&opts);

    _ = c.av_dict_set(&opts, "rtmp_live", "live", 0);

    // Open network connection with retry
    var attempts: u32 = 0;
    const max_attempts: u32 = 3;
    var result: c_int = -1;

    while (attempts < max_attempts) : (attempts += 1) {
        result = c.avio_open2(&format_ctx.*.pb, url.ptr, c.AVIO_FLAG_WRITE, null, &opts);

        if (result >= 0) {
            std.debug.print("Connected to stream server\n", .{});
            break;
        }

        var errbuf: [128]u8 = undefined;
        _ = c.av_strerror(result, &errbuf, errbuf.len);
        std.debug.print("Connection attempt {d} failed: Error number {d} occurred: {s}\n", .{ attempts + 1, result, errbuf });

        if (attempts + 1 < max_attempts) {
            std.debug.print("Retrying in 1 second...\n", .{});
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    if (result < 0) {
        return error.ConnectionFailed;
    }

    // Write format header
    if (c.avformat_write_header(format_ctx, &opts) < 0) {
        return error.HeaderFailed;
    }

    return .{
        .format_ctx = format_ctx,
        .stream_index = stream.*.index,
    };
}

pub fn write(self: RTMPOutput, packet: [*c]c.AVPacket) !void {
    packet.*.stream_index = self.stream_index;
    if (c.av_interleaved_write_frame(self.format_ctx, packet) < 0) {
        return error.WriteFailed;
    }
}

pub fn deinit(self: *RTMPOutput) void {
    if (self.format_ctx) |ctx| {
        _ = c.av_write_trailer(ctx);
        if (ctx.*.pb != null) {
            _ = c.avio_closep(&ctx.*.pb);
        }
        c.avformat_free_context(ctx);
        self.format_ctx = null;
    }
}
