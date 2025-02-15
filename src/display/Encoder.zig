// Encoder helps convert between ffmpeg frame formats, and to encoded images like PNGs

const std = @import("std");
const c = @import("c.zig").c;
const Frame = @import("Frame.zig");
const Image = @import("Image.zig");

const Encoder = @This();

// FFmpeg context for encoding
codec_ctx: [*c]c.AVCodecContext,

const PixelFormat = enum(c_int) {
    BGR0 = c.AV_PIX_FMT_BGR0,
    RGB24 = c.AV_PIX_FMT_RGB24,
    _,
};

pub const ScaleMode = enum {
    /// Scale to exact dimensions
    Exact,
    /// Scale maintaining aspect ratio, fitting within max dimensions. Can end up smaller than max dimensions.
    AspectFit,
    /// Scale maintaining aspect ratio, filling max dimensions. Can end up larger than max dimensions.
    AspectFill,
};

pub const ScaleOptions = struct {
    width: ?c_int = null,
    height: ?c_int = null,
    mode: ScaleMode = .Exact,
};

pub fn init(width: c_int, height: c_int) !Encoder {
    // Find encoder for PNG
    const codec = c.avcodec_find_encoder(c.AV_CODEC_ID_PNG);
    if (codec == null) return error.NoEncoder;

    // Allocate codec context
    var codec_ctx = c.avcodec_alloc_context3(codec);
    if (codec_ctx == null) return error.CodecContextFailed;
    errdefer c.avcodec_free_context(&codec_ctx);

    // Set codec parameters
    codec_ctx.*.width = width;
    codec_ctx.*.height = height;
    codec_ctx.*.pix_fmt = c.AV_PIX_FMT_RGB24;
    codec_ctx.*.time_base = .{ .num = 1, .den = 1 };

    // Open codec
    if (c.avcodec_open2(codec_ctx, codec, null) < 0) return error.CodecOpenFailed;

    return Encoder{
        .codec_ctx = codec_ctx,
    };
}

pub fn deinit(self: *Encoder) void {
    c.avcodec_free_context(&self.codec_ctx);
}

fn getScaledDimensions(orig_width: c_int, orig_height: c_int, options: ScaleOptions) Frame.Dimensions {
    const target_w = options.width orelse orig_width;
    const target_h = options.height orelse orig_height;

    // If no scaling requested or exact mode, use target dimensions
    if (options.mode == .Exact or (options.width == null and options.height == null)) {
        return .{ .width = target_w, .height = target_h };
    }

    // Calculate scaling ratios
    const width_ratio = @as(f32, @floatFromInt(target_w)) / @as(f32, @floatFromInt(orig_width));
    const height_ratio = @as(f32, @floatFromInt(target_h)) / @as(f32, @floatFromInt(orig_height));

    // Choose scale based on mode
    const scale = switch (options.mode) {
        .AspectFit => @min(width_ratio, height_ratio),
        .AspectFill => @max(width_ratio, height_ratio),
        .Exact => unreachable, // handled above
    };

    return .{
        .width = @intFromFloat(@round(@as(f32, @floatFromInt(orig_width)) * scale)),
        .height = @intFromFloat(@round(@as(f32, @floatFromInt(orig_height)) * scale)),
    };
}

fn convertFrame(frame: Frame, target_format: PixelFormat, scale_options: ScaleOptions) !Frame {
    const dimensions: Frame.Dimensions = if (scale_options.height != null and scale_options.width != null)
        getScaledDimensions(frame.dimensions.width, frame.dimensions.height, scale_options)
    else
        frame.dimensions;

    // Create conversion context
    const sws = c.sws_getContext(
        frame.dimensions.width,
        frame.dimensions.height,
        frame.raw_frame.*.format,
        dimensions.width,
        dimensions.height,
        @intFromEnum(target_format),
        c.SWS_BILINEAR,
        null,
        null,
        null,
    );
    if (sws == null) return error.SwsError;
    defer c.sws_freeContext(sws);

    // Allocate output frame
    var out_frame = c.av_frame_alloc();
    if (out_frame == null) return error.FrameAllocFailed;
    errdefer c.av_frame_free(&out_frame);

    // Set output frame properties
    out_frame.*.format = @intFromEnum(target_format);
    out_frame.*.width = dimensions.width;
    out_frame.*.height = dimensions.height;

    // Allocate output frame buffers
    const ret = c.av_frame_get_buffer(out_frame, 0);
    if (ret < 0) return error.BufferAllocFailed;

    // Do the conversion
    const scale_ret = c.sws_scale(
        sws,
        &frame.raw_frame.*.data[0],
        &frame.raw_frame.*.linesize[0],
        0,
        frame.dimensions.height,
        &out_frame.*.data[0],
        &out_frame.*.linesize[0],
    );
    if (scale_ret < 0) return error.ScaleFailed;

    return Frame.init(out_frame);
}

pub fn encode(self: Encoder, frame: Frame, allocator: std.mem.Allocator, scale_options: ScaleOptions) !Image {
    // Convert frame to RGB24 (required for PNG) and scale if requested
    var rgb_frame = try convertFrame(frame, .RGB24, scale_options);
    defer rgb_frame.deinit();

    // Update codec context dimensions if scaled
    if (scale_options.width != null and scale_options.height != null) {
        self.codec_ctx.*.width = rgb_frame.dimensions.width;
        self.codec_ctx.*.height = rgb_frame.dimensions.height;
    }

    // Send frame to encoder
    if (c.avcodec_send_frame(self.codec_ctx, rgb_frame.raw_frame) < 0) {
        return error.SendFrameFailed;
    }

    // Get encoded packet
    var packet = c.av_packet_alloc();
    if (packet == null) return error.PacketAllocFailed;
    defer c.av_packet_free(&packet);

    // Receive encoded packet
    const ret = c.avcodec_receive_packet(self.codec_ctx, packet);
    if (ret < 0) return error.ReceivePacketFailed;

    // Copy packet data to our buffer
    const bytes = try allocator.alloc(u8, @intCast(packet.*.size));
    @memcpy(bytes, packet.*.data[0..@intCast(packet.*.size)]);

    return Image{
        .bytes = bytes,
        .encoding = .PNG,
        .allocator = allocator,
    };
}
