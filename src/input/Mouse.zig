const std = @import("std");
const win = std.os.windows;
const c = @import("c.zig").c;

const Mouse = @This();

scale_x: f32,
scale_y: f32,

pub const Coordinates = struct {
    x: i32,
    y: i32,
    space: Space = Space.Physical, // Users interract using physical coordinates

    pub const Space = enum {
        Virtual,
        Physical,
    };

    pub fn toVirtual(self: Coordinates, scale_x: f32, scale_y: f32) Coordinates {
        if (self.space == .Virtual) {
            return self;
        }
        return .{
            .x = @intFromFloat(@as(f32, @floatFromInt(self.x)) / scale_x),
            .y = @intFromFloat(@as(f32, @floatFromInt(self.y)) / scale_y),
            .space = .Virtual,
        };
    }

    pub fn toPhysical(self: Coordinates, scale_x: f32, scale_y: f32) Coordinates {
        if (self.space == .Physical) {
            return self;
        }
        return .{
            .x = @intFromFloat(@as(f32, @floatFromInt(self.x)) * scale_x),
            .y = @intFromFloat(@as(f32, @floatFromInt(self.y)) * scale_y),
            .space = .Physical,
        };
    }
};

pub fn new(display_width: u32, display_height: u32) Mouse {
    // Windows Mouse APIs use a virtual screen coordinate system, which may be different from the physical screen.
    // We need to scale the user provided mouse coordinates (physical screen) to virtual screen coordinates.
    const virtual_width = @as(f32, @floatFromInt(c.GetSystemMetrics(c.SM_CXVIRTUALSCREEN)));
    const virtual_height = @as(f32, @floatFromInt(c.GetSystemMetrics(c.SM_CYVIRTUALSCREEN)));
    const scale_x = @as(f32, @floatFromInt(display_width)) / virtual_width;
    const scale_y = @as(f32, @floatFromInt(display_height)) / virtual_height;

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

    var coord = Coordinates{
        .x = @intCast(point.x),
        .y = @intCast(point.y),
        .space = .Virtual,
    };
    coord = coord.toPhysical(mouse.scale_x, mouse.scale_y);
    return coord;
}

pub fn move(mouse: *Mouse, target: Coordinates) !void {
    const target_scaled = target.toVirtual(mouse.scale_x, mouse.scale_y);
    if (c.SetCursorPos(target_scaled.x, target_scaled.y) == 0) {
        return error.SetCursorPosFailed;
    }

    // Ensure it arrived
    const arrived = try mouse.coordinates();
    if (arrived.x != target.x or arrived.y != target.y) {
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
