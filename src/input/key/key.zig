const std = @import("std");

pub const Key = enum(u16) {
    // Basic keys
    Escape = 0x01,
    @"1" = 0x02,
    @"2" = 0x03,
    @"3" = 0x04,
    @"4" = 0x05,
    @"5" = 0x06,
    @"6" = 0x07,
    @"7" = 0x08,
    @"8" = 0x09,
    @"9" = 0x0A,
    @"0" = 0x0B,
    Minus = 0x0C,
    Equals = 0x0D,
    Tab = 0x0F,

    // Letter keys
    Q = 0x10,
    W = 0x11,
    E = 0x12,
    R = 0x13,
    T = 0x14,
    Y = 0x15,
    U = 0x16,
    I = 0x17,
    O = 0x18,
    P = 0x19,
    LeftBracket = 0x1A,
    RightBracket = 0x1B,
    Return = 0x1C,
    LControl = 0x1D,
    A = 0x1E,
    S = 0x1F,
    D = 0x20,
    F = 0x21,
    G = 0x22,
    H = 0x23,
    J = 0x24,
    K = 0x25,
    L = 0x26,
    Semicolon = 0x27,
    Quote = 0x28,
    Grave = 0x29,
    LShift = 0x2A,
    BackSlash = 0x2B,
    Z = 0x2C,
    X = 0x2D,
    C = 0x2E,
    V = 0x2F,
    B = 0x30,
    N = 0x31,
    M = 0x32,
    Comma = 0x33,
    Period = 0x34,
    ForwardSlash = 0x35,
    RShift = 0x36,
    LMenu = 0x38,
    Space = 0x39,
    Capital = 0x3A,

    // Function keys
    F1 = 0x3B,
    F2 = 0x3C,
    F3 = 0x3D,
    F4 = 0x3E,
    F5 = 0x3F,
    F6 = 0x40,
    F7 = 0x41,
    F8 = 0x42,
    F9 = 0x43,
    F10 = 0x44,

    // Navigation keys - need extended codes
    Home = 0xE047,
    PageUp = 0xE049,
    End = 0xE04F,
    PageDown = 0xE051,
    Insert = 0xE052,
    Delete = 0xE053,
    BackSpace = 0x0E, // Not extended

    // Arrow keys - need extended codes
    UpArrow = 0xE048,
    LeftArrow = 0xE04B,
    RightArrow = 0xE04D,
    DownArrow = 0xE050,

    // Windows keys - already correct
    LSuper = 0xE05B,

    pub const Category = enum {
        Basic,
        Letter,
        Number,
        Symbol,
        Function,
        Navigation,
        Arrow,
        Modifier,
    };

    pub fn getCategory(self: Key) Category {
        return switch (self) {
            .Escape, .Tab, .Return, .Space, .Capital, .BackSpace => .Basic,
            .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .@"9", .@"0" => .Number,
            .A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M, .N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z => .Letter,
            .Minus, .Equals, .LeftBracket, .RightBracket, .Semicolon, .Quote, .Grave, .BackSlash, .Comma, .Period, .ForwardSlash => .Symbol,
            .F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10 => .Function,
            .Home, .End, .PageUp, .PageDown, .Insert, .Delete => .Navigation,
            .UpArrow, .DownArrow, .LeftArrow, .RightArrow => .Arrow,
            .LControl, .LShift, .RShift, .LMenu, .LSuper => .Modifier,
        };
    }

    pub fn isModifier(self: Key) bool {
        return self.getCategory() == .Modifier;
    }
};

test "abc key categories" {
    try std.testing.expect(Key.A.getCategory() == .Letter);
    try std.testing.expect(Key.@"1".getCategory() == .Number);
    try std.testing.expect(Key.F1.getCategory() == .Function);
    try std.testing.expect(Key.Home.getCategory() == .Navigation);
    try std.testing.expect(Key.UpArrow.getCategory() == .Arrow);
    try std.testing.expect(Key.LShift.getCategory() == .Modifier);
    try std.testing.expect(Key.Minus.getCategory() == .Symbol);
    try std.testing.expect(Key.Space.getCategory() == .Basic);
    try std.testing.expect(Key.LSuper.getCategory() == .Modifier);
}

test "abc modifiers" {
    try std.testing.expect(Key.LShift.isModifier());
    try std.testing.expect(Key.LControl.isModifier());
    try std.testing.expect(Key.LMenu.isModifier());
    try std.testing.expect(Key.LSuper.isModifier());
    try std.testing.expect(!Key.A.isModifier());
    try std.testing.expect(!Key.Space.isModifier());
}
