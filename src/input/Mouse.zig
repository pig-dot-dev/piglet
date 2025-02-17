const std = @import("std");
const win = std.os.windows;
const c = @import("c.zig").c;

const Mouse = @This();

pub const Coordinates = struct {
    x: i32,
    y: i32,
};

scale_x: f32,
scale_y: f32,

pub fn new(display_width: u32, display_height: u32) Mouse {
    // Windows Mouse APIs use a virtual screen coordinate system, which may be different from the physical screen.
    // We need to scale the user provided mouse coordinates (physical screen) to virtual screen coordinates.
    const virtual_width = @as(f32, @floatFromInt(c.GetSystemMetrics(c.SM_CXVIRTUALSCREEN)));
    const virtual_height = @as(f32, @floatFromInt(c.GetSystemMetrics(c.SM_CYVIRTUALSCREEN)));

    // Now we scale FROM physical TO virtual
    const scale_x = virtual_width / @as(f32, @floatFromInt(display_width));
    const scale_y = virtual_height / @as(f32, @floatFromInt(display_height));

    return .{
        .scale_x = scale_x,
        .scale_y = scale_y,
    };
}

pub fn coordinates(mouse: *Mouse) !Coordinates {
    var point: c.POINT = undefined;
    if (c.GetCursorPos(&point) == 0) {
        return error.GetCursorPosFailed;
    }

    // Convert virtual coordinates back to physical
    return Coordinates{
        .x = @intFromFloat(@as(f32, @floatFromInt(point.x)) / mouse.scale_x),
        .y = @intFromFloat(@as(f32, @floatFromInt(point.y)) / mouse.scale_y),
    };
}

pub fn move(mouse: *Mouse, target: Coordinates) !void {
    // Convert physical coordinates to virtual
    const virtual_x: c_int = @intFromFloat(@as(f32, @floatFromInt(target.x)) * mouse.scale_x);
    const virtual_y: c_int = @intFromFloat(@as(f32, @floatFromInt(target.y)) * mouse.scale_y);

    if (c.SetCursorPos(virtual_x, virtual_y) == 0) {
        return error.SetCursorPosFailed;
    }

    // Ensure it arrived (in physical coordinates) with +-2px tolerance (due to floating point errors)
    const arrived = try mouse.coordinates();
    if ((arrived.x >= target.x + 2 or arrived.x <= target.x - 2) or (arrived.y >= target.y + 2 or arrived.y <= target.y - 2)) {
        return error.MouseMoveFailed;
    }
}

pub const Button = enum {
    left,
    right,
};

pub fn click(mouse: *Mouse, button: Button, down: bool, target: Coordinates) !void {
    // First move to target position
    try mouse.move(target);

    var flags: c_ulong = 0;
    switch (button) {
        .left => {
            switch (down) {
                true => flags = c.MOUSEEVENTF_LEFTDOWN,
                false => flags = c.MOUSEEVENTF_LEFTUP,
            }
        },
        .right => {
            switch (down) {
                true => flags = c.MOUSEEVENTF_RIGHTDOWN,
                false => flags = c.MOUSEEVENTF_RIGHTUP,
            }
        },
    }

    var input = c.INPUT{
        .type = c.INPUT_MOUSE,
        .unnamed_0 = .{
            .mi = .{
                .dx = 0, // No movement needed
                .dy = 0, // No movement needed
                .mouseData = 0,
                .dwFlags = flags,
                .time = 0,
                .dwExtraInfo = 0,
            },
        },
    };

    if (c.SendInput(1, &input, @sizeOf(c.INPUT)) != 1) {
        return error.SendInputFailed;
    }
}
