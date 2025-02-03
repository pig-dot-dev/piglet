const std = @import("std");
const Key = @import("key.zig").Key;

pub const KeyMapping = struct {
    key: Key,
    shifted: bool = false,
};

// Maps a character to its keyboard representation
pub fn charToKey(c: u8) ?KeyMapping {
    return switch (c) {
        // Letters
        'a'...'z' => KeyMapping{
            .key = @enumFromInt(letterToScanCode(std.ascii.toUpper(c))),
        },
        'A'...'Z' => KeyMapping{
            .key = @enumFromInt(letterToScanCode(c)),
            .shifted = true,
        },

        // Numbers and their shifted variants
        '0'...'9' => KeyMapping{
            .key = @enumFromInt(numberToScanCode(c)),
        },
        '!' => KeyMapping{ .key = .@"1", .shifted = true },
        '@' => KeyMapping{ .key = .@"2", .shifted = true },
        '#' => KeyMapping{ .key = .@"3", .shifted = true },
        '$' => KeyMapping{ .key = .@"4", .shifted = true },
        '%' => KeyMapping{ .key = .@"5", .shifted = true },
        '^' => KeyMapping{ .key = .@"6", .shifted = true },
        '&' => KeyMapping{ .key = .@"7", .shifted = true },
        '*' => KeyMapping{ .key = .@"8", .shifted = true },
        '(' => KeyMapping{ .key = .@"9", .shifted = true },
        ')' => KeyMapping{ .key = .@"0", .shifted = true },

        // Basic symbols
        '-' => KeyMapping{ .key = .Minus },
        '_' => KeyMapping{ .key = .Minus, .shifted = true },
        '=' => KeyMapping{ .key = .Equals },
        '+' => KeyMapping{ .key = .Equals, .shifted = true },
        '[' => KeyMapping{ .key = .LeftBracket },
        '{' => KeyMapping{ .key = .LeftBracket, .shifted = true },
        ']' => KeyMapping{ .key = .RightBracket },
        '}' => KeyMapping{ .key = .RightBracket, .shifted = true },
        ';' => KeyMapping{ .key = .Semicolon },
        ':' => KeyMapping{ .key = .Semicolon, .shifted = true },
        '\'' => KeyMapping{ .key = .Quote },
        '"' => KeyMapping{ .key = .Quote, .shifted = true },
        '`' => KeyMapping{ .key = .Grave },
        '~' => KeyMapping{ .key = .Grave, .shifted = true },
        '\\' => KeyMapping{ .key = .BackSlash },
        '|' => KeyMapping{ .key = .BackSlash, .shifted = true },
        ',' => KeyMapping{ .key = .Comma },
        '<' => KeyMapping{ .key = .Comma, .shifted = true },
        '.' => KeyMapping{ .key = .Period },
        '>' => KeyMapping{ .key = .Period, .shifted = true },
        '/' => KeyMapping{ .key = .ForwardSlash },
        '?' => KeyMapping{ .key = .ForwardSlash, .shifted = true },

        // Whitespace
        ' ' => KeyMapping{ .key = .Space },
        '\t' => KeyMapping{ .key = .Tab },
        '\n' => KeyMapping{ .key = .Return },

        else => null,
    };
}

// Maps an XDO-style token to its keyboard representation
pub const XDOMapping = struct {
    key: Key,
    shifted: bool = false,
    is_modifier: bool = false,
};

pub fn xdoTokenToKey(token: []const u8) ?XDOMapping {
    const name_map = std.StaticStringMap(XDOMapping).initComptime(.{
        // Modifiers (these take precedence)
        .{ "ctrl", .{ .key = .LControl, .is_modifier = true } },
        .{ "control", .{ .key = .LControl, .is_modifier = true } },
        .{ "alt", .{ .key = .LMenu, .is_modifier = true } },
        .{ "shift", .{ .key = .LShift, .is_modifier = true } },
        .{ "super", .{ .key = .LSuper, .is_modifier = true } },

        // Special keys
        .{ "escape", .{ .key = .Escape } },
        .{ "esc", .{ .key = .Escape } },
        .{ "return", .{ .key = .Return } },
        .{ "enter", .{ .key = .Return } },
        .{ "space", .{ .key = .Space } },
        .{ "tab", .{ .key = .Tab } },

        // Navigation keys
        .{ "windows", .{ .key = .LSuper } },
        .{ "home", .{ .key = .Home } },
        .{ "end", .{ .key = .End } },
        .{ "pageup", .{ .key = .PageUp } },
        .{ "page_up", .{ .key = .PageUp } },
        .{ "pagedown", .{ .key = .PageDown } },
        .{ "page_down", .{ .key = .PageDown } },
        .{ "insert", .{ .key = .Insert } },
        .{ "delete", .{ .key = .Delete } },
        .{ "backspace", .{ .key = .BackSpace } },
        .{ "up", .{ .key = .UpArrow } },
        .{ "uparrow", .{ .key = .UpArrow } },
        .{ "up_arrow", .{ .key = .UpArrow } },
        .{ "down", .{ .key = .DownArrow } },
        .{ "downarrow", .{ .key = .DownArrow } },
        .{ "down_arrow", .{ .key = .DownArrow } },
        .{ "left", .{ .key = .LeftArrow } },
        .{ "leftarrow", .{ .key = .LeftArrow } },
        .{ "left_arrow", .{ .key = .LeftArrow } },
        .{ "right", .{ .key = .RightArrow } },
        .{ "rightarrow", .{ .key = .RightArrow } },
        .{ "right_arrow", .{ .key = .RightArrow } },

        // Function keys
        .{ "f1", .{ .key = .F1 } },
        .{ "f2", .{ .key = .F2 } },
        .{ "f3", .{ .key = .F3 } },
        .{ "f4", .{ .key = .F4 } },
        .{ "f5", .{ .key = .F5 } },
        .{ "f6", .{ .key = .F6 } },
        .{ "f7", .{ .key = .F7 } },
        .{ "f8", .{ .key = .F8 } },
        .{ "f9", .{ .key = .F9 } },
        .{ "f10", .{ .key = .F10 } },

        // Symbol names that map to shifted number keys
        .{ "exclam", .{ .key = .@"1", .shifted = true } },
        .{ "at", .{ .key = .@"2", .shifted = true } },
        .{ "numbersign", .{ .key = .@"3", .shifted = true } },
        .{ "number_sign", .{ .key = .@"3", .shifted = true } },
        .{ "dollar", .{ .key = .@"4", .shifted = true } },
        .{ "percent", .{ .key = .@"5", .shifted = true } },
        .{ "asciicircum", .{ .key = .@"6", .shifted = true } },
        .{ "ascii_circum", .{ .key = .@"6", .shifted = true } },
        .{ "ascii_circumflex", .{ .key = .@"6", .shifted = true } },
        .{ "circumflex", .{ .key = .@"6", .shifted = true } },
        .{ "ascii_caret", .{ .key = .@"6", .shifted = true } },
        .{ "caret", .{ .key = .@"6", .shifted = true } },
        .{ "ampersand", .{ .key = .@"7", .shifted = true } },
        .{ "asterisk", .{ .key = .@"8", .shifted = true } },
        .{ "parenleft", .{ .key = .@"9", .shifted = true } },
        .{ "paren_left", .{ .key = .@"9", .shifted = true } },
        .{ "parenright", .{ .key = .@"0", .shifted = true } },
        .{ "paren_right", .{ .key = .@"0", .shifted = true } },

        // Symbol names that map to symbols
        .{ "minus", .{ .key = .Minus } },
        .{ "underscore", .{ .key = .Minus, .shifted = true } },
        .{ "equal", .{ .key = .Equals } },
        .{ "plus", .{ .key = .Equals, .shifted = true } },
        .{ "bracketleft", .{ .key = .LeftBracket } },
        .{ "bracket_left", .{ .key = .LeftBracket } },
        .{ "braceleft", .{ .key = .LeftBracket, .shifted = true } },
        .{ "brace_left", .{ .key = .LeftBracket, .shifted = true } },
        .{ "bracketright", .{ .key = .RightBracket } },
        .{ "bracket_right", .{ .key = .RightBracket } },
        .{ "braceright", .{ .key = .RightBracket, .shifted = true } },
        .{ "brace_right", .{ .key = .RightBracket, .shifted = true } },
    });

    // Try the name map first
    if (name_map.get(token)) |mapping| {
        return mapping;
    }

    // If it's a single char, try the char mapping
    if (token.len == 1) {
        if (charToKey(token[0])) |mapping| {
            return .{
                .key = mapping.key,
                .shifted = mapping.shifted,
                .is_modifier = mapping.key.isModifier(),
            };
        }
    }

    return null;
}

// Helpers that belong in this layer since they're about key representation
fn letterToScanCode(c: u8) u8 {
    return switch (c) {
        'A' => 0x1E,
        'B' => 0x30,
        'C' => 0x2E,
        'D' => 0x20,
        'E' => 0x12,
        'F' => 0x21,
        'G' => 0x22,
        'H' => 0x23,
        'I' => 0x17,
        'J' => 0x24,
        'K' => 0x25,
        'L' => 0x26,
        'M' => 0x32,
        'N' => 0x31,
        'O' => 0x18,
        'P' => 0x19,
        'Q' => 0x10,
        'R' => 0x13,
        'S' => 0x1F,
        'T' => 0x14,
        'U' => 0x16,
        'V' => 0x2F,
        'W' => 0x11,
        'X' => 0x2D,
        'Y' => 0x15,
        'Z' => 0x2C,
        else => unreachable,
    };
}

fn numberToScanCode(c: u8) u8 {
    return switch (c) {
        '1' => 0x02,
        '2' => 0x03,
        '3' => 0x04,
        '4' => 0x05,
        '5' => 0x06,
        '6' => 0x07,
        '7' => 0x08,
        '8' => 0x09,
        '9' => 0x0A,
        '0' => 0x0B,
        else => unreachable,
    };
}

test "char to key - basic" {
    const test_cases = .{
        .{ 'a', Key.A, false },
        .{ 'A', Key.A, true },
        .{ '1', Key.@"1", false },
        .{ '!', Key.@"1", true },
        .{ '-', Key.Minus, false },
        .{ '_', Key.Minus, true },
    };

    inline for (test_cases) |case| {
        const mapping = charToKey(case[0]) orelse unreachable;
        try std.testing.expectEqual(case[1], mapping.key);
        try std.testing.expectEqual(case[2], mapping.shifted);
    }
}

test "xdo token to key - modifiers" {
    const test_cases = .{
        .{ "ctrl", Key.LControl, true },
        .{ "control", Key.LControl, true },
        .{ "alt", Key.LMenu, true },
        .{ "shift", Key.LShift, true },
    };

    inline for (test_cases) |case| {
        const mapping = xdoTokenToKey(case[0]) orelse unreachable;
        try std.testing.expectEqual(case[1], mapping.key);
        try std.testing.expectEqual(case[2], mapping.is_modifier);
    }
}

test "xdo token to key - special names" {
    const test_cases = .{
        .{ "parenleft", Key.@"9", true },
        .{ "parenright", Key.@"0", true },
        .{ "numbersign", Key.@"3", true },
        .{ "bracketleft", Key.LeftBracket, false },
        .{ "braceleft", Key.LeftBracket, true },
    };

    inline for (test_cases) |case| {
        const mapping = xdoTokenToKey(case[0]) orelse unreachable;
        try std.testing.expectEqual(case[1], mapping.key);
        try std.testing.expectEqual(case[2], mapping.shifted);
    }
}
