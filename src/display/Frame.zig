const std = @import("std");
const c = @import("c.zig");

const Frame = @This();

raw_frame: *c.AVFrame,
format: PixelFormat,
dimensions: struct {
    width: c_int,
    height: c_int,
},

pub fn deinit(_: *Frame) void {
    // TODO: Free AVFrame
    @panic("TODO");
}

/// Convert frame to a different pixel format and/or size
pub fn convertTo(_: Frame, _: std.mem.Allocator, _: ConvertOptions) ![]u8 {
    // TODO: Use swscale to convert frame
    @panic("TODO");
}

pub const PixelFormat = enum {
    RGB24,
    BGR24,
    RGBA,
    YUV420P,
};

pub const ConvertOptions = struct {
    format: PixelFormat,
    max_width: ?c_int = null,
    max_height: ?c_int = null,
};
