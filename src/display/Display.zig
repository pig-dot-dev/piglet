// Display is the high-level api for piglet into the display

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
    std.debug.print("Display dimensions: {}x{}\n", .{ capture.dimensions.width, capture.dimensions.height });
    return Display{
        .capture = capture,
        .encoder = encoder,
    };
}

pub fn deinit(self: *Display) void {
    self.encoder.deinit();
    self.capture.deinit();
}

pub fn screenshot(self: *Display, allocator: std.mem.Allocator, scale_options: Encoder.ScaleOptions) !Image {
    var frame = try self.capture.getFrame();
    defer frame.deinit();
    return try self.encoder.encode(frame, allocator, scale_options);
}

pub fn width(self: Display) u32 {
    // note: these are the dimensions of the capture, not the encoded image
    return @intCast(self.capture.dimensions.width);
}

pub fn height(self: Display) u32 {
    // note: these are the dimensions of the capture, not the encoded image
    return @intCast(self.capture.dimensions.height);
}
