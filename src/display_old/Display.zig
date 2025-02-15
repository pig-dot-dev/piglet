const std = @import("std");
const win = std.os.windows;
const zigimg = @import("zigimg"); // note we use the version pinned to zig 0.13, see build.zig.zon for commit

const D3D11 = @import("D3D11.zig");
const DXGI = @import("DXGI.zig");
const Frame = @import("Frame.zig");

const Display = @This();
// The following is a diagram of the relationships between the various objects
// D3D11 Device → DXGI Device → DXGI Adapter → DXGI Output → DXGI Output1 → DXGI Output Duplication
//
// D3D11 Device: A software abstraction on top of the physical graphics devices.
// DXGI Device: A subset of the D3D11 device, with a more specific interface for reading information about the device.
// DXGI Adapter: A single physical graphics device, like a GPU. We'll use the default one.
// DXGI Output: The output to all monitors.
// DXGI Output1: The output to the primary monitor.
// DXGI Output Duplication: A software layer on a monitor that allows us to duplicate it into our program.

// internals
d3d11_device: D3D11.Device,
dxgi_device: DXGI.Device,
dxgi_adapter: DXGI.Adapter,
dxgi_output: DXGI.Output,
dxgi_output1: DXGI.Output1,
dxgi_output_duplication: DXGI.Output1.Duplication,

// our own stuff
frame_converter: Frame.Converter,
dimensions: struct {
    width: u32,
    height: u32,
},

pub fn init() !Display {
    var d3d11_device = try D3D11.Device.init();
    errdefer d3d11_device.deinit();

    var dxgi_device = try DXGI.Device.init(d3d11_device);
    errdefer dxgi_device.deinit();

    var dxgi_adapter = try DXGI.Adapter.init(dxgi_device);
    errdefer dxgi_adapter.deinit();

    var dxgi_output = try DXGI.Output.init(dxgi_adapter);
    errdefer dxgi_output.deinit();

    var dxgi_output1 = try DXGI.Output1.init(dxgi_output);
    errdefer dxgi_output1.deinit();

    var dxgi_output_duplication = try DXGI.Output1.Duplication.init(dxgi_output1, d3d11_device);
    errdefer dxgi_output_duplication.deinit();

    // Get dimensions from output description
    // NOTE you must first create Output1 before calling this function, despite it being on the Output struct
    // Otherwise the dimensions are incorrect
    const dims = try dxgi_output.getDimensions();
    std.debug.print("Screen dimensions: {d}x{d}\n", .{ dims.width, dims.height });

    // FrameConverter preinitializes the staging texture so it's fast to use later
    const frame_converter = try Frame.Converter.init(d3d11_device, dims.width, dims.height);

    return Display{
        .frame_converter = frame_converter,
        .d3d11_device = d3d11_device,
        .dxgi_device = dxgi_device,
        .dxgi_adapter = dxgi_adapter,
        .dxgi_output = dxgi_output,
        .dxgi_output1 = dxgi_output1,
        .dxgi_output_duplication = dxgi_output_duplication,
        .dimensions = .{
            .width = dims.width,
            .height = dims.height,
        },
    };
}

pub fn deinit(self: *Display) void {
    self.dxgi_output_duplication.deinit();
    self.dxgi_output1.deinit();
    self.dxgi_output.deinit();
    self.dxgi_adapter.deinit();
    self.dxgi_device.deinit();
    self.d3d11_device.deinit();
}

pub fn getFrame(self: Display) !Frame {
    return try Frame.init(
        self.dxgi_output_duplication,
    );
}

/// capture a Frame and then return it as a PNG image
/// note: this can take a minute for a large screen in debug builds. Use release-safe builds for production.
/// TODO: make this faster, pretty rediculous
pub fn getPNG(self: Display, allocator: std.mem.Allocator) ![]u8 {
    var frame = try self.getFrame();
    defer frame.deinit();

    const size = self.frame_converter.requiredBufferSize();
    const image_data = try allocator.alloc(u8, size);
    defer allocator.free(image_data);

    // Convert to RGBA32 and write to memory
    var s = std.time.nanoTimestamp();
    try self.frame_converter.getPixels(&frame, image_data);
    s = std.time.nanoTimestamp();
    var image = try zigimg.Image.fromRawPixels(allocator, self.width(), self.height(), image_data, .bgra32);
    try image.convert(.rgba32);
    defer image.deinit();

    // Save to buffer
    s = std.time.nanoTimestamp();

    // Reuse our image_data buffer
    const written = try image.writeToMemory(image_data, .{ .png = .{} });
    s = std.time.nanoTimestamp();
    const png_data = try allocator.dupe(u8, written);
    return png_data;
}

pub fn width(self: Display) u32 {
    return self.dimensions.width;
}

pub fn height(self: Display) u32 {
    return self.dimensions.height;
}
