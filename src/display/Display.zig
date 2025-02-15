const std = @import("std");
const Capture = @import("Capture.zig");

const Display = @This();

// internals
capture: Capture,

pub fn init() !Display {
    const capture = try Capture.init();
    return Display{
        .capture = capture,
    };
}

pub fn deinit(self: *Display) void {
    self.capture.deinit();
}
