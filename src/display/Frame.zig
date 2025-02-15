const std = @import("std");
const c = @import("c.zig").c;

const Frame = @This();

raw_frame: [*c]c.AVFrame,
format: PixelFormat,
dimensions: struct {
    width: c_int,
    height: c_int,
},

pub const PixelFormat = enum(c_int) {
    BGR0 = c.AV_PIX_FMT_BGR0,
    RGB24 = c.AV_PIX_FMT_RGB24,
    _,
};

pub fn init(raw_frame: [*c]c.AVFrame, format: PixelFormat) Frame {
    return Frame{
        .raw_frame = raw_frame,
        .format = format,
        .dimensions = .{
            .width = raw_frame.*.width,
            .height = raw_frame.*.height,
        },
    };
}

pub fn deinit(self: *Frame) void {
    c.av_frame_free(&self.raw_frame);
}

pub const ConvertOptions = struct {
    format: PixelFormat,
    max_width: ?c_int = null,
    max_height: ?c_int = null,
};

/// Convert frame to a different pixel format and/or size
pub fn convertTo(self: Frame, options: ConvertOptions) !Frame {
    // Create conversion context
    const sws = c.sws_getContext(
        self.dimensions.width,
        self.dimensions.height,
        @intFromEnum(self.format),
        options.max_width orelse self.dimensions.width,
        options.max_height orelse self.dimensions.height,
        @intFromEnum(options.format),
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
    out_frame.*.format = @intFromEnum(options.format);
    out_frame.*.width = options.max_width orelse self.dimensions.width;
    out_frame.*.height = options.max_height orelse self.dimensions.height;

    // Allocate output frame buffers
    const ret = c.av_frame_get_buffer(out_frame, 0);
    if (ret < 0) return error.BufferAllocFailed;

    // Do the conversion
    const scale_ret = c.sws_scale(
        sws,
        &self.raw_frame.*.data[0],
        &self.raw_frame.*.linesize[0],
        0,
        self.dimensions.height,
        &out_frame.*.data[0],
        &out_frame.*.linesize[0],
    );
    if (scale_ret < 0) return error.ScaleFailed;

    return Frame.init(out_frame, options.format);
}
