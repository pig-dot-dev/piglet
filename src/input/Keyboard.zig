const std = @import("std");
const win = std.os.windows;
const c = @import("c.zig").c;

// Key is the direct keycode representation of a physical key
// KeySequence is the highest-level api for converting a string of characters to a sequence of key events
const Key = @import("key/key.zig").Key;
const KeySequence = @import("key/KeySequence.zig");

const Keyboard = @This();

allocator: std.mem.Allocator,

pub fn new(allocator: std.mem.Allocator) Keyboard {
    return .{
        .allocator = allocator,
    };
}

// Send a single key event
fn sendKeyEvent(self: *Keyboard, key: Key, down: bool) !void {
    _ = self;
    var flags: u32 = 0;
    var scan_code = @intFromEnum(key);

    // Check if it's an extended key (has high byte set)
    if (scan_code > 0xFF) {
        flags |= c.KEYEVENTF_EXTENDEDKEY;
        scan_code &= 0xFF;
    }

    if (!down) {
        flags |= c.KEYEVENTF_KEYUP;
    }

    var input = c.INPUT{
        .type = c.INPUT_KEYBOARD,
        .unnamed_0 = .{
            .ki = .{
                .wVk = 0, // We're using scan codes
                .wScan = scan_code,
                .dwFlags = flags | c.KEYEVENTF_SCANCODE,
                .time = 0,
                .dwExtraInfo = 0,
            },
        },
    };

    if (c.SendInput(1, &input, @sizeOf(c.INPUT)) != 1) {
        return error.SendInputFailed;
    }
}

// Execute a sequence of key events
pub fn inputString(self: *Keyboard, sequence: []const u8) !void {
    var key_sequence = try KeySequence.initString(self.allocator, sequence);
    defer key_sequence.deinit();

    for (key_sequence.events) |event| {
        try self.sendKeyEvent(event.key, event.down);
    }
}

// Execute a sequence in XDO format (e.g., "ctrl+c ctrl+v")
pub fn inputXDO(self: *Keyboard, sequence: []const u8) !void {
    var key_sequence = try KeySequence.initXDO(self.allocator, sequence);
    defer key_sequence.deinit();

    for (key_sequence.events) |event| {
        try self.sendKeyEvent(event.key, event.down);
    }
}
