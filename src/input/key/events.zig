const std = @import("std");
const Key = @import("key.zig").Key;
const mapping = @import("mapping.zig");
const KeyMapping = mapping.KeyMapping;
const XDOMapping = mapping.XDOMapping;

pub const KeyEvent = struct {
    key: Key,
    down: bool,
};

pub const EventGenerator = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(KeyEvent),

    pub fn init(allocator: std.mem.Allocator) EventGenerator {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(KeyEvent).init(allocator),
        };
    }

    pub fn deinit(self: *EventGenerator) void {
        self.events.deinit();
    }

    // Core event generation
    fn pressKey(self: *EventGenerator, key: Key) !void {
        try self.events.append(.{ .key = key, .down = true });
    }

    fn releaseKey(self: *EventGenerator, key: Key) !void {
        try self.events.append(.{ .key = key, .down = false });
    }

    fn pressAndReleaseKey(self: *EventGenerator, key: Key) !void {
        try self.pressKey(key);
        try self.releaseKey(key);
    }

    // Handle shifted keys
    pub fn generateKeyMapping(self: *EventGenerator, key_mapping: KeyMapping) !void {
        if (key_mapping.shifted) {
            try self.pressKey(.LShift);
        }

        try self.pressAndReleaseKey(key_mapping.key);

        if (key_mapping.shifted) {
            try self.releaseKey(.LShift);
        }
    }

    // Handle XDO-style mappings
    pub fn generateXDOMapping(self: *EventGenerator, key_mapping: XDOMapping) !void {
        if (key_mapping.shifted) {
            try self.pressKey(.LShift);
        }

        try self.pressAndReleaseKey(key_mapping.key);

        if (key_mapping.shifted) {
            try self.releaseKey(.LShift);
        }
    }

    // Handle multiple mappings with common modifiers
    pub fn generateXDOMappingWithModifiers(self: *EventGenerator, key_mappings: []const XDOMapping, modifiers: []const Key) !void {
        // Press all modifiers in order
        for (modifiers) |modifier| {
            try self.pressKey(modifier);
        }

        // Press and release all regular keys
        for (key_mappings) |km| {
            if (!km.is_modifier) {
                try self.generateXDOMapping(km);
            }
        }

        // Release modifiers in reverse order
        var i: usize = modifiers.len;
        while (i > 0) {
            i -= 1;
            try self.releaseKey(modifiers[i]);
        }
    }

    // Take ownership of the generated events
    pub fn finish(self: *EventGenerator) ![]const KeyEvent {
        return try self.events.toOwnedSlice();
    }
};

test "basic key events" {
    var gen = EventGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try gen.pressAndReleaseKey(.A);

    const events = try gen.finish();
    defer std.testing.allocator.free(events);

    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(Key.A, events[0].key);
    try std.testing.expect(events[0].down);
    try std.testing.expectEqual(Key.A, events[1].key);
    try std.testing.expect(!events[1].down);
}

test "shifted key events" {
    var gen = EventGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const key_mapping = KeyMapping{ .key = .A, .shifted = true };
    try gen.generateKeyMapping(key_mapping);

    const events = try gen.finish();
    defer std.testing.allocator.free(events);

    try std.testing.expectEqual(@as(usize, 4), events.len);
    try std.testing.expectEqual(Key.LShift, events[0].key);
    try std.testing.expect(events[0].down);
    try std.testing.expectEqual(Key.A, events[1].key);
    try std.testing.expect(events[1].down);
    try std.testing.expectEqual(Key.A, events[2].key);
    try std.testing.expect(!events[2].down);
    try std.testing.expectEqual(Key.LShift, events[3].key);
    try std.testing.expect(!events[3].down);
}

test "multiple modifiers" {
    var gen = EventGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const modifiers = [_]Key{ .LControl, .LShift };
    const mappings = [_]XDOMapping{.{ .key = .A }};

    try gen.generateXDOMappingWithModifiers(&mappings, &modifiers);

    const events = try gen.finish();
    defer std.testing.allocator.free(events);

    try std.testing.expectEqual(@as(usize, 6), events.len);

    // Check press order
    try std.testing.expectEqual(Key.LControl, events[0].key);
    try std.testing.expect(events[0].down);
    try std.testing.expectEqual(Key.LShift, events[1].key);
    try std.testing.expect(events[1].down);

    // Check key press/release
    try std.testing.expectEqual(Key.A, events[2].key);
    try std.testing.expect(events[2].down);
    try std.testing.expectEqual(Key.A, events[3].key);
    try std.testing.expect(!events[3].down);

    // Check release order (reverse of press)
    try std.testing.expectEqual(Key.LShift, events[4].key);
    try std.testing.expect(!events[4].down);
    try std.testing.expectEqual(Key.LControl, events[5].key);
    try std.testing.expect(!events[5].down);
}
