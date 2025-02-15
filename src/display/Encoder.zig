const std = @import("std");
const c = @import("c.zig").c;
const Frame = @import("Frame.zig");
const Image = @import("Image.zig");

const Encoder = @This();

// FFmpeg context for encoding
codec_ctx: [*c]c.AVCodecContext,

pub fn init(width: c_int, height: c_int) !Encoder {
    // Find encoder for PNG
    const codec = c.avcodec_find_encoder(c.AV_CODEC_ID_PNG);

    // Allocate codec context
    var codec_ctx = c.avcodec_alloc_context3(codec);
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

pub fn encode(self: Encoder, frame: Frame, allocator: std.mem.Allocator) !Image {
    // Send frame to encoder
    if (c.avcodec_send_frame(self.codec_ctx, frame.raw_frame) < 0) {
        return error.SendFrameFailed;
    }

    // Get encoded packet
    var packet = c.av_packet_alloc();
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
