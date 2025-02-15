const std = @import("std");
const c = @import("c.zig").c;
const Frame = @import("Frame.zig");

const Capture = @This();

// FFmpeg context for screen capture
format_ctx: [*c]c.AVFormatContext,
codec_ctx: [*c]c.AVCodecContext,
stream_index: c_int,

// Dimensions of the capture
dimensions: struct {
    width: c_int,
    height: c_int,
},

pub fn init() !Capture {
    // Register all devices (including gdigrab)
    c.avdevice_register_all();

    // Initialize format context
    var format_ctx: ?*c.AVFormatContext = null;
    const input_format = c.av_find_input_format("gdigrab") orelse return error.NoGdigrab;

    // Open the input device (screen capture)
    const ret = c.avformat_open_input(
        &format_ctx,
        "desktop",
        input_format,
        null,
    );
    if (ret < 0) return error.OpenInputFailed;
    if (format_ctx == null) return error.OpenInputFailed;

    // Get stream info
    if (c.avformat_find_stream_info(format_ctx, null) < 0) {
        c.avformat_close_input(&format_ctx);
        return error.StreamInfoFailed;
    }

    // Find video stream
    var stream: [*c]c.struct_AVStream = undefined;
    var codecpar: *c.struct_AVCodecParameters = undefined;
    const stream_index = blk: {
        var i: c_uint = 0;
        while (i < format_ctx.?.nb_streams) : (i += 1) {
            stream = format_ctx.?.streams[i];
            codecpar = stream.*.codecpar;
            if (codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
                break :blk @as(c_int, @intCast(i));
            }
        }
        return error.NoVideoStream;
    };

    // Get decoder
    const codec = c.avcodec_find_decoder(codecpar.*.codec_id);

    // Allocate codec context
    var codec_ctx = c.avcodec_alloc_context3(codec);
    errdefer c.avcodec_free_context(&codec_ctx);

    // Copy params from stream
    if (c.avcodec_parameters_to_context(
        codec_ctx,
        codecpar,
    ) < 0) return error.CodecParamsFailed;

    // Open codec
    if (c.avcodec_open2(codec_ctx, codec, null) < 0) return error.CodecOpenFailed;

    return Capture{
        .format_ctx = format_ctx.?,
        .codec_ctx = codec_ctx,
        .stream_index = stream_index,
        .dimensions = .{
            .width = codec_ctx.*.width,
            .height = codec_ctx.*.height,
        },
    };
}

pub fn deinit(self: *Capture) void {
    c.avcodec_free_context(&self.codec_ctx);
    c.avformat_close_input(&self.format_ctx);
}

/// Get a single frame from the capture pipeline
/// Caller owns the returned frame and must call frame.deinit()
pub fn getFrame(_: Capture) !Frame {
    // TODO: Grab and decode a frame
    @panic("TODO");
}
