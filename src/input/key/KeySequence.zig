const std = @import("std");
const Key = @import("key.zig").Key;
const mapping = @import("mapping.zig");
const events = @import("events.zig");
const KeyEvent = events.KeyEvent;
const EventGenerator = events.EventGenerator;

const KeySequence = @This();

allocator: std.mem.Allocator,
events: []const KeyEvent,

pub fn deinit(self: *const KeySequence) void {
    self.allocator.free(self.events);
}

// Create sequence from a string of raw characters
pub fn initString(allocator: std.mem.Allocator, str: []const u8) !KeySequence {
    var generator = EventGenerator.init(allocator);
    defer generator.deinit();

    for (str) |c| {
        const key_mapping = mapping.charToKey(c) orelse return error.InvalidChar;
        try generator.generateKeyMapping(key_mapping);
    }

    return KeySequence{
        .allocator = allocator,
        .events = try generator.finish(),
    };
}

// Create sequence from XDO style input (e.g., "ctrl+c ctrl+v")
pub fn initXDO(allocator: std.mem.Allocator, str: []const u8) !KeySequence {
    var generator = EventGenerator.init(allocator);
    defer generator.deinit();

    // Handle multiple space-separated commands
    var commands = std.mem.split(u8, str, " ");
    while (commands.next()) |command| {
        try processXDOCommand(allocator, &generator, command);
    }

    return KeySequence{
        .allocator = allocator,
        .events = try generator.finish(),
    };
}

fn processXDOCommand(allocator: std.mem.Allocator, generator: *EventGenerator, command: []const u8) !void {
    var modifiers = std.ArrayList(Key).init(allocator);
    defer modifiers.deinit();

    var keys = std.ArrayList(mapping.XDOMapping).init(allocator);
    defer keys.deinit();

    // Split command into parts (e.g., "ctrl+shift+a" -> ["ctrl", "shift", "a"])
    var parts = std.mem.split(u8, command, "+");
    while (parts.next()) |part| {
        const lowercase = try std.ascii.allocLowerString(allocator, part);
        defer allocator.free(lowercase);
        const key_mapping = mapping.xdoTokenToKey(lowercase) orelse return error.InvalidToken;
        if (key_mapping.is_modifier) {
            try modifiers.append(key_mapping.key);
        } else {
            try keys.append(key_mapping);
        }
    }

    try generator.generateXDOMappingWithModifiers(keys.items, modifiers.items);
}

test "string sequence - basic" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initString(allocator, "a");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.events.len);
    try std.testing.expectEqual(Key.A, result.events[0].key);
    try std.testing.expect(result.events[0].down);
    try std.testing.expectEqual(Key.A, result.events[1].key);
    try std.testing.expect(!result.events[1].down);
}

test "string sequence - shifted" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initString(allocator, "A");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.events.len);
    try std.testing.expectEqual(Key.LShift, result.events[0].key);
    try std.testing.expect(result.events[0].down);
    try std.testing.expectEqual(Key.A, result.events[1].key);
    try std.testing.expect(result.events[1].down);
    try std.testing.expectEqual(Key.A, result.events[2].key);
    try std.testing.expect(!result.events[2].down);
    try std.testing.expectEqual(Key.LShift, result.events[3].key);
    try std.testing.expect(!result.events[3].down);
}

test "string sequence - multiple" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initString(allocator, "Hello, World! @#$%^&*()");
    defer result.deinit();

    const expected = [_]KeyEvent{
        // H
        .{ .key = .LShift, .down = true },
        .{ .key = .H, .down = true },
        .{ .key = .H, .down = false },
        .{ .key = .LShift, .down = false },
        // e
        .{ .key = .E, .down = true },
        .{ .key = .E, .down = false },
        // l
        .{ .key = .L, .down = true },
        .{ .key = .L, .down = false },
        // l
        .{ .key = .L, .down = true },
        .{ .key = .L, .down = false },
        // o
        .{ .key = .O, .down = true },
        .{ .key = .O, .down = false },
        // ,
        .{ .key = .Comma, .down = true },
        .{ .key = .Comma, .down = false },
        // space
        .{ .key = .Space, .down = true },
        .{ .key = .Space, .down = false },
        // W
        .{ .key = .LShift, .down = true },
        .{ .key = .W, .down = true },
        .{ .key = .W, .down = false },
        .{ .key = .LShift, .down = false },
        // o
        .{ .key = .O, .down = true },
        .{ .key = .O, .down = false },
        // r
        .{ .key = .R, .down = true },
        .{ .key = .R, .down = false },
        // l
        .{ .key = .L, .down = true },
        .{ .key = .L, .down = false },
        // d
        .{ .key = .D, .down = true },
        .{ .key = .D, .down = false },
        // !
        .{ .key = .LShift, .down = true },
        .{ .key = .@"1", .down = true },
        .{ .key = .@"1", .down = false },
        .{ .key = .LShift, .down = false },
        // space
        .{ .key = .Space, .down = true },
        .{ .key = .Space, .down = false },
        // @
        .{ .key = .LShift, .down = true },
        .{ .key = .@"2", .down = true },
        .{ .key = .@"2", .down = false },
        .{ .key = .LShift, .down = false },
        // #
        .{ .key = .LShift, .down = true },
        .{ .key = .@"3", .down = true },
        .{ .key = .@"3", .down = false },
        .{ .key = .LShift, .down = false },
        // $
        .{ .key = .LShift, .down = true },
        .{ .key = .@"4", .down = true },
        .{ .key = .@"4", .down = false },
        .{ .key = .LShift, .down = false },
        // %
        .{ .key = .LShift, .down = true },
        .{ .key = .@"5", .down = true },
        .{ .key = .@"5", .down = false },
        .{ .key = .LShift, .down = false },
        // ^
        .{ .key = .LShift, .down = true },
        .{ .key = .@"6", .down = true },
        .{ .key = .@"6", .down = false },
        .{ .key = .LShift, .down = false },
        // &
        .{ .key = .LShift, .down = true },
        .{ .key = .@"7", .down = true },
        .{ .key = .@"7", .down = false },
        .{ .key = .LShift, .down = false },
        // *
        .{ .key = .LShift, .down = true },
        .{ .key = .@"8", .down = true },
        .{ .key = .@"8", .down = false },
        .{ .key = .LShift, .down = false },
        // (
        .{ .key = .LShift, .down = true },
        .{ .key = .@"9", .down = true },
        .{ .key = .@"9", .down = false },
        .{ .key = .LShift, .down = false },
        // )
        .{ .key = .LShift, .down = true },
        .{ .key = .@"0", .down = true },
        .{ .key = .@"0", .down = false },
        .{ .key = .LShift, .down = false },
    };

    try std.testing.expectEqual(expected.len, result.events.len);
    for (expected, 0..) |evt, i| {
        try std.testing.expectEqual(evt.key, result.events[i].key);
        try std.testing.expectEqual(evt.down, result.events[i].down);
    }
}

test "string sequence - character pairs" {
    const allocator = std.testing.allocator;

    // Test all shifted/unshifted pairs
    const cases = .{
        .{ "[{", .LeftBracket },
        .{ "]}", .RightBracket },
        .{ "-_", .Minus },
        .{ "=+", .Equals },
        .{ ",<", .Comma },
        .{ ".>", .Period },
        .{ "/?", .ForwardSlash },
        .{ ";:", .Semicolon },
        .{ "'\"", .Quote },
        .{ "`~", .Grave },
        .{ "\\|", .BackSlash },
    };

    inline for (cases) |case| {
        const result = try KeySequence.initString(allocator, case[0]);
        defer result.deinit();

        // First char - unshifted
        try std.testing.expectEqual(case[1], result.events[0].key);
        try std.testing.expect(result.events[0].down);
        try std.testing.expectEqual(case[1], result.events[1].key);
        try std.testing.expect(!result.events[1].down);

        // Second char - shifted version
        try std.testing.expectEqual(Key.LShift, result.events[2].key);
        try std.testing.expect(result.events[2].down);
        try std.testing.expectEqual(case[1], result.events[3].key);
        try std.testing.expect(result.events[3].down);
        try std.testing.expectEqual(case[1], result.events[4].key);
        try std.testing.expect(!result.events[4].down);
        try std.testing.expectEqual(Key.LShift, result.events[5].key);
        try std.testing.expect(!result.events[5].down);
    }
}

test "string sequence - whitespace" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initString(allocator, " \t\n");
    defer result.deinit();

    const expected = [_]KeyEvent{
        // space
        .{ .key = .Space, .down = true },
        .{ .key = .Space, .down = false },
        // tab
        .{ .key = .Tab, .down = true },
        .{ .key = .Tab, .down = false },
        // newline
        .{ .key = .Return, .down = true },
        .{ .key = .Return, .down = false },
    };

    try std.testing.expectEqual(expected.len, result.events.len);
    for (expected, 0..) |evt, i| {
        try std.testing.expectEqual(evt.key, result.events[i].key);
        try std.testing.expectEqual(evt.down, result.events[i].down);
    }
}

test "string sequence - number symbols" {
    const allocator = std.testing.allocator;

    // All shifted number keys
    const result = try KeySequence.initString(allocator, ")!@#$%^&*(");
    defer result.deinit();

    const numbers = [_]Key{ .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .@"9" };
    var i: usize = 0;
    while (i < result.events.len) : (i += 4) {
        try std.testing.expectEqual(Key.LShift, result.events[i].key);
        try std.testing.expect(result.events[i].down);
        try std.testing.expectEqual(numbers[i / 4], result.events[i + 1].key);
        try std.testing.expect(result.events[i + 1].down);
        try std.testing.expectEqual(numbers[i / 4], result.events[i + 2].key);
        try std.testing.expect(!result.events[i + 2].down);
        try std.testing.expectEqual(Key.LShift, result.events[i + 3].key);
        try std.testing.expect(!result.events[i + 3].down);
    }
}

test "xdo sequence - shifted plus modifiers" {
    const allocator = std.testing.allocator;

    // Test shift as both a character shifter and a modifier
    // Note: Multiple shift press/release events are expected and harmless.
    // This happens because:
    // 1. XDO "shift+A" treats shift as a modifier
    // 2. Capital "A" itself requires shift
    // Since keyboard shift state is binary (pressed/not pressed),
    // multiple shift events don't cause issues.
    const result = try KeySequence.initXDO(allocator, "shift+A ctrl+shift+B");
    defer result.deinit();

    const expected = [_]KeyEvent{
        // shift+A
        .{ .key = .LShift, .down = true },
        .{ .key = .A, .down = true },
        .{ .key = .A, .down = false },
        .{ .key = .LShift, .down = false },
        // ctrl+shift+B
        .{ .key = .LControl, .down = true },
        .{ .key = .LShift, .down = true },
        .{ .key = .B, .down = true },
        .{ .key = .B, .down = false },
        .{ .key = .LShift, .down = false },
        .{ .key = .LControl, .down = false },
    };

    try std.testing.expectEqualSlices(KeyEvent, &expected, result.events);
}

test "xdo sequence - navigation keys" {
    const allocator = std.testing.allocator;

    // Test all navigation keys with various modifiers
    const result = try KeySequence.initXDO(allocator, "Home End PageUp PageDown Insert Delete " ++
        "UpArrow DownArrow LeftArrow RightArrow " ++
        "ctrl+Home shift+End alt+Insert");
    defer result.deinit();

    const nav_keys = [_]Key{
        .Home,    .End,       .PageUp,    .PageDown,   .Insert, .Delete,
        .UpArrow, .DownArrow, .LeftArrow, .RightArrow,
    };

    // First 10 keys should be just press/release
    var i: usize = 0;
    for (nav_keys) |key| {
        try std.testing.expectEqual(key, result.events[i].key);
        try std.testing.expect(result.events[i].down);
        try std.testing.expectEqual(key, result.events[i + 1].key);
        try std.testing.expect(!result.events[i + 1].down);
        i += 2;
    }

    // ctrl+Home
    try std.testing.expectEqual(Key.LControl, result.events[i].key);
    try std.testing.expect(result.events[i].down);
    try std.testing.expectEqual(Key.Home, result.events[i + 1].key);
    try std.testing.expect(result.events[i + 1].down);
    try std.testing.expectEqual(Key.Home, result.events[i + 2].key);
    try std.testing.expect(!result.events[i + 2].down);
    try std.testing.expectEqual(Key.LControl, result.events[i + 3].key);
    try std.testing.expect(!result.events[i + 3].down);
    i += 4;

    // shift+End
    try std.testing.expectEqual(Key.LShift, result.events[i].key);
    try std.testing.expect(result.events[i].down);
    try std.testing.expectEqual(Key.End, result.events[i + 1].key);
    try std.testing.expect(result.events[i + 1].down);
    try std.testing.expectEqual(Key.End, result.events[i + 2].key);
    try std.testing.expect(!result.events[i + 2].down);
    try std.testing.expectEqual(Key.LShift, result.events[i + 3].key);
    try std.testing.expect(!result.events[i + 3].down);
    i += 4;

    // alt+Insert
    try std.testing.expectEqual(Key.LMenu, result.events[i].key);
    try std.testing.expect(result.events[i].down);
    try std.testing.expectEqual(Key.Insert, result.events[i + 1].key);
    try std.testing.expect(result.events[i + 1].down);
    try std.testing.expectEqual(Key.Insert, result.events[i + 2].key);
    try std.testing.expect(!result.events[i + 2].down);
    try std.testing.expectEqual(Key.LMenu, result.events[i + 3].key);
    try std.testing.expect(!result.events[i + 3].down);
}

test "xdo sequence - mixed case names" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initXDO(allocator, "CTRL+A ctrl+B Control+C control+D " ++
        "SHIFT+E shift+F Shift+G " ++
        "ALT+H alt+I Alt+J");
    defer result.deinit();

    // All these should produce identical sequences just with different letters
    var i: usize = 0;
    const letters = [_]Key{ .A, .B, .C, .D, .E, .F, .G, .H, .I, .J };
    const mods = [_]Key{
        .LControl, .LControl, .LControl, .LControl,
        .LShift,   .LShift,   .LShift,   .LMenu,
        .LMenu,    .LMenu,
    };

    while (i < result.events.len) : (i += 4) {
        const idx = i / 4;
        try std.testing.expectEqual(mods[idx], result.events[i].key);
        try std.testing.expect(result.events[i].down);
        try std.testing.expectEqual(letters[idx], result.events[i + 1].key);
        try std.testing.expect(result.events[i + 1].down);
        try std.testing.expectEqual(letters[idx], result.events[i + 2].key);
        try std.testing.expect(!result.events[i + 2].down);
        try std.testing.expectEqual(mods[idx], result.events[i + 3].key);
        try std.testing.expect(!result.events[i + 3].down);
    }
}

test "xdo sequence - function keys" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initXDO(allocator, "F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 " ++
        "ctrl+F1 alt+F5 shift+F10");
    defer result.deinit();

    // First test plain function keys
    var i: usize = 0;
    const f_keys = [_]Key{ .F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10 };

    for (f_keys) |key| {
        try std.testing.expectEqual(key, result.events[i].key);
        try std.testing.expect(result.events[i].down);
        try std.testing.expectEqual(key, result.events[i + 1].key);
        try std.testing.expect(!result.events[i + 1].down);
        i += 2;
    }

    // ctrl+F1
    try std.testing.expectEqual(Key.LControl, result.events[i].key);
    try std.testing.expect(result.events[i].down);
    try std.testing.expectEqual(Key.F1, result.events[i + 1].key);
    try std.testing.expect(result.events[i + 1].down);
    try std.testing.expectEqual(Key.F1, result.events[i + 2].key);
    try std.testing.expect(!result.events[i + 2].down);
    try std.testing.expectEqual(Key.LControl, result.events[i + 3].key);
    try std.testing.expect(!result.events[i + 3].down);
    i += 4;

    // alt+F5
    try std.testing.expectEqual(Key.LMenu, result.events[i].key);
    try std.testing.expect(result.events[i].down);
    try std.testing.expectEqual(Key.F5, result.events[i + 1].key);
    try std.testing.expect(result.events[i + 1].down);
    try std.testing.expectEqual(Key.F5, result.events[i + 2].key);
    try std.testing.expect(!result.events[i + 2].down);
    try std.testing.expectEqual(Key.LMenu, result.events[i + 3].key);
    try std.testing.expect(!result.events[i + 3].down);
    i += 4;

    // shift+F10
    try std.testing.expectEqual(Key.LShift, result.events[i].key);
    try std.testing.expect(result.events[i].down);
    try std.testing.expectEqual(Key.F10, result.events[i + 1].key);
    try std.testing.expect(result.events[i + 1].down);
    try std.testing.expectEqual(Key.F10, result.events[i + 2].key);
    try std.testing.expect(!result.events[i + 2].down);
    try std.testing.expectEqual(Key.LShift, result.events[i + 3].key);
    try std.testing.expect(!result.events[i + 3].down);
}

test "xdo sequence - multiple commands" {
    const allocator = std.testing.allocator;

    const result = try KeySequence.initXDO(allocator, "ctrl+c ctrl+v");
    defer result.deinit();

    const expected = [_]KeyEvent{
        // First command (ctrl+c)
        .{ .key = .LControl, .down = true },
        .{ .key = .C, .down = true },
        .{ .key = .C, .down = false },
        .{ .key = .LControl, .down = false },
        // Second command (ctrl+v)
        .{ .key = .LControl, .down = true },
        .{ .key = .V, .down = true },
        .{ .key = .V, .down = false },
        .{ .key = .LControl, .down = false },
    };

    try std.testing.expectEqualSlices(KeyEvent, &expected, result.events);
}
