// Frame is a zig wrapper around AVFrame
// This is a raw (unformatted) frame, passed from the capture device to the encoder

const std = @import("std");
const c = @import("c.zig").c;

const Frame = @This();

raw_frame: [*c]c.AVFrame,
dimensions: Dimensions,
pub const Dimensions = struct { width: c_int, height: c_int };

pub fn init(raw_frame: [*c]c.AVFrame) Frame {
    return Frame{
        .raw_frame = raw_frame,
        .dimensions = .{
            .width = raw_frame.*.width,
            .height = raw_frame.*.height,
        },
    };
}

pub fn deinit(self: *Frame) void {
    c.av_frame_free(&self.raw_frame);
}

pub fn create(width: c_int, height: c_int, format: c_int) !Frame {
    var frame = c.av_frame_alloc();
    if (frame == null) return error.FrameAllocFailed;
    errdefer c.av_frame_free(&frame);

    frame.*.format = format;
    frame.*.width = width;
    frame.*.height = height;

    // Allocate actual frame buffers
    const ret = c.av_frame_get_buffer(frame, 0);
    if (ret < 0) return error.FrameBufferAllocFailed;

    return init(frame);
}
