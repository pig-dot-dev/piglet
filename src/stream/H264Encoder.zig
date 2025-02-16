const std = @import("std");
const c = @import("../display/c.zig").c;
const Frame = @import("../display/Frame.zig");
const EncoderConfig = @import("EncoderConfig.zig");

const H264Encoder = @This();

/// FFmpeg codec context for H.264 encoding
codec_ctx: [*c]c.AVCodecContext,

/// Initialize H.264 encoder with given dimensions and configuration
pub fn init(width: c_int, height: c_int, config: EncoderConfig) !H264Encoder {
    // Find H.264 encoder
    const codec = c.avcodec_find_encoder(c.AV_CODEC_ID_H264);
    if (codec == null) return error.NoEncoder;

    // Allocate codec context
    var codec_ctx = c.avcodec_alloc_context3(codec);
    if (codec_ctx == null) return error.CodecContextFailed;
    errdefer c.avcodec_free_context(&codec_ctx);

    // Set basic video parameters
    codec_ctx.*.width = width;
    codec_ctx.*.height = height;
    codec_ctx.*.time_base = .{ .num = 1, .den = @intFromFloat(config.fps) };
    codec_ctx.*.framerate = .{ .num = @intFromFloat(config.fps), .den = 1 };
    codec_ctx.*.pix_fmt = c.AV_PIX_FMT_YUV420P; // Required for H.264
    codec_ctx.*.gop_size = @intCast(config.gop_size);
    codec_ctx.*.max_b_frames = 0; // No B-frames for low latency
    codec_ctx.*.bit_rate = @intCast(config.bitrate);

    // Additional settings for streaming
    codec_ctx.*.flags |= c.AV_CODEC_FLAG_GLOBAL_HEADER; // Required for RTMP
    codec_ctx.*.flags2 |= c.AV_CODEC_FLAG2_FAST; // Prefer speed over quality

    // Remove rate control - let x264 handle it
    codec_ctx.*.rc_min_rate = 0;
    codec_ctx.*.rc_max_rate = 0;
    codec_ctx.*.rc_buffer_size = 0;

    // Set H.264 specific options
    _ = c.av_opt_set(codec_ctx.*.priv_data, "preset", "ultrafast", 0); // Match FFmpeg command
    _ = c.av_opt_set(codec_ctx.*.priv_data, "tune", "zerolatency", 0);
    _ = c.av_opt_set(codec_ctx.*.priv_data, "profile", "baseline", 0);

    // Open codec
    if (c.avcodec_open2(codec_ctx, codec, null) < 0) {
        return error.CodecOpenFailed;
    }

    return .{ .codec_ctx = codec_ctx };
}

/// Clean up encoder resources
pub fn deinit(self: *H264Encoder) void {
    if (self.codec_ctx != null) {
        c.avcodec_free_context(&self.codec_ctx);
    }
}

/// Encode a frame to H.264
pub fn encode(self: H264Encoder, frame: Frame) ![*c]c.AVPacket {
    // Convert frame to YUV420P (required for H.264)
    var yuv_frame = try convertToYUV420P(frame);
    defer yuv_frame.deinit();

    // Create packet for encoded data
    var packet = c.av_packet_alloc();
    if (packet == null) return error.PacketAllocFailed;
    errdefer c.av_packet_free(&packet);

    // Send frame to encoder
    const send_result = c.avcodec_send_frame(self.codec_ctx, yuv_frame.raw_frame);
    if (send_result < 0) {
        return error.EncodeSendFailed;
    }

    // Receive encoded packet
    while (true) {
        const ret = c.avcodec_receive_packet(self.codec_ctx, packet);
        if (ret == 0) {
            return packet;
        } else if (ret == c.AVERROR(c.EAGAIN)) {
            // Need to send more frames
            continue;
        } else if (ret == c.AVERROR_EOF) {
            return error.EncoderFlushed;
        } else {
            return error.EncodeReceiveFailed;
        }
    }
}

/// Convert frame to YUV420P pixel format
fn convertToYUV420P(frame: Frame) !Frame {
    const sws_ctx = c.sws_getContext(
        frame.raw_frame.*.width,
        frame.raw_frame.*.height,
        @intCast(frame.raw_frame.*.format),
        frame.raw_frame.*.width,
        frame.raw_frame.*.height,
        c.AV_PIX_FMT_YUV420P,
        c.SWS_BILINEAR,
        null,
        null,
        null,
    );
    if (sws_ctx == null) return error.SwsContextFailed;
    defer c.sws_freeContext(sws_ctx);

    // Create new YUV frame
    const yuv_frame = try Frame.create(
        frame.raw_frame.*.width,
        frame.raw_frame.*.height,
        c.AV_PIX_FMT_YUV420P,
    );

    // Convert to YUV420P
    _ = c.sws_scale(
        sws_ctx,
        @ptrCast(&frame.raw_frame.*.data),
        &frame.raw_frame.*.linesize,
        0,
        frame.raw_frame.*.height,
        @ptrCast(&yuv_frame.raw_frame.*.data),
        &yuv_frame.raw_frame.*.linesize,
    );

    return yuv_frame;
}
