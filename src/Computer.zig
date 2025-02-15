const std = @import("std");
const Display = @import("display/Display.zig");
const Keyboard = @import("input/Keyboard.zig");
const Mouse = @import("input/Mouse.zig");

const Computer = @This();

display: Display,
// keyboard: Keyboard,
// mouse: Mouse,

pub fn init(_: std.mem.Allocator) !Computer {
    const display = try Display.init();
    // const keyboard = Keyboard.new(allocator);
    // const mouse = Mouse.new(display.width(), display.height());
    return .{
        .display = display,
        // .keyboard = keyboard,
        // .mouse = mouse,
    };
}

pub fn deinit(self: *Computer) void {
    self.display.deinit();
}
