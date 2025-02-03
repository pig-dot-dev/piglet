const std = @import("std");
const win = std.os.windows;
const Display = @import("display/Display.zig");
const Frame = @import("display/Frame.zig");
const Mouse = @import("input/mouse.zig").Mouse;
const Keyboard = @import("input/Keyboard.zig").Keyboard;
const server = @import("server.zig");

const Computer = @import("Computer.zig");

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();

    var computer = try Computer.init(allocator);
    defer computer.deinit();

    try server.Run(allocator, &computer, 3000);
}
