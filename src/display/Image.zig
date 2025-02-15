const std = @import("std");

const Image = @This();

bytes: []u8,
encoding: Encoding,
allocator: std.mem.Allocator,

pub const Encoding = enum {
    PNG,
    // Add more formats later:
    // JPEG,
    // WEBP,
};

pub fn deinit(self: *Image) void {
    self.allocator.free(self.bytes);
}
