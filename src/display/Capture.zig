/// Capture represents the device display input stream
/// It is used to capture raw images from the display
const std = @import("std");
const c = @import("c.zig").c;
const Frame = @import("Frame.zig");

const Capture = @This();

// FFmpeg context for screen capture
format_ctx: [*c]c.AVFormatContext,
codec_ctx: [*c]c.AVCodecContext,
stream_index: c_int,

mutex: std.Thread.Mutex = .{},

// Dimensions of the capture
dimensions: struct {
    width: c_int,
    height: c_int,
},

pub fn init() !Capture {
    // Set FFmpeg log level to only show errors
    c.av_log_set_level(c.AV_LOG_ERROR);

    // Register all devices (including gdigrab)
    c.avdevice_register_all();

    // Initialize format context
    var format_ctx: ?*c.AVFormatContext = null;
    const input_format = c.av_find_input_format("gdigrab");
    if (input_format == null) return error.NoGdigrab;

    // Set options to draw mouse cursor
    var options: ?*c.AVDictionary = null;
    _ = c.av_dict_set(&options, "draw_mouse", "1", 0);

    // Open the input device (screen capture)
    const ret = c.avformat_open_input(
        &format_ctx,
        "desktop",
        input_format,
        &options,
    );
    if (ret < 0) return error.OpenInputFailed;
    if (format_ctx == null) return error.OpenInputFailed;

    // Get stream info
    if (c.avformat_find_stream_info(format_ctx, null) < 0) {
        c.avformat_close_input(&format_ctx);
        return error.StreamInfoFailed;
    }

    // Find video stream
    var stream_index: c_int = -1;
    var i: c_uint = 0;
    while (i < format_ctx.?.nb_streams) : (i += 1) {
        if (format_ctx.?.streams[i].*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
            stream_index = @intCast(i);
            break;
        }
    }
    if (stream_index == -1) {
        c.avformat_close_input(&format_ctx);
        return error.NoVideoStream;
    }

    // Get codec parameters
    const codecpar = format_ctx.?.streams[@intCast(stream_index)].*.codecpar;

    // Find decoder
    const codec = c.avcodec_find_decoder(codecpar.*.codec_id);
    if (codec == null) {
        c.avformat_close_input(&format_ctx);
        return error.NoDecoder;
    }

    // Create codec context
    var codec_ctx = c.avcodec_alloc_context3(codec);
    if (codec_ctx == null) {
        c.avformat_close_input(&format_ctx);
        return error.CodecContextFailed;
    }

    // Fill codec context from parameters
    if (c.avcodec_parameters_to_context(codec_ctx, codecpar) < 0) {
        c.avcodec_free_context(&codec_ctx);
        c.avformat_close_input(&format_ctx);
        return error.CodecParamsFailed;
    }

    // Open codec
    if (c.avcodec_open2(codec_ctx, codec, null) < 0) {
        c.avcodec_free_context(&codec_ctx);
        c.avformat_close_input(&format_ctx);
        return error.CodecOpenFailed;
    }

    return Capture{
        .format_ctx = format_ctx,
        .codec_ctx = codec_ctx,
        .stream_index = stream_index,
        .dimensions = .{
            .width = codecpar.*.width,
            .height = codecpar.*.height,
        },
    };
}

pub fn deinit(self: *Capture) void {
    c.avcodec_free_context(&self.codec_ctx);
    c.avformat_close_input(&self.format_ctx);
}

/// Get a single frame from the capture device
/// Caller owns the returned frame and must call frame.deinit()
pub fn getFrame(self: *Capture) !Frame {
    // Allocate packet for reading
    var packet = c.av_packet_alloc();
    if (packet == null) return error.PacketAllocFailed;
    defer c.av_packet_free(&packet);

    self.mutex.lock();
    defer self.mutex.unlock();

    // Read frames until we get a video frame
    while (true) {
        const ret = c.av_read_frame(self.format_ctx, packet);
        if (ret < 0) return error.ReadFrameFailed;
        defer c.av_packet_unref(packet);

        // Skip packets from other streams
        if (packet.*.stream_index != self.stream_index) continue;

        // Allocate frame for decoding
        var frame = c.av_frame_alloc();
        if (frame == null) return error.FrameAllocFailed;
        errdefer c.av_frame_free(&frame);

        // Send packet to decoder
        if (c.avcodec_send_packet(self.codec_ctx, packet) < 0) return error.SendPacketFailed;

        // Get decoded frame
        const decode_ret = c.avcodec_receive_frame(self.codec_ctx, frame);
        if (decode_ret < 0) {
            if (decode_ret == c.AVERROR(c.EAGAIN)) continue;
            return error.ReceiveFrameFailed;
        }

        // Successfully got a frame
        return Frame.init(frame);
    }
}
