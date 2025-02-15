const std = @import("std");
const Capture = @import("Capture.zig");
const Encoder = @import("Encoder.zig");
const Image = @import("Image.zig");

const Display = @This();

// internals
capture: Capture,
encoder: Encoder,

pub fn init() !Display {
    const capture = try Capture.init();
    const encoder = try Encoder.init(capture.dimensions.width, capture.dimensions.height);
    return Display{
        .capture = capture,
        .encoder = encoder,
    };
}

pub fn deinit(self: *Display) void {
    self.encoder.deinit();
    self.capture.deinit();
}

pub fn screenshot(self: *Display, allocator: std.mem.Allocator) !Image {
    var frame = try self.capture.getFrame();
    defer frame.deinit();
    return try self.encoder.encode(frame, allocator);
}
