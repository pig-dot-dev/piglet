const std = @import("std");
const DXGI = @import("DXGI.zig");
const D3D11 = @import("D3D11.zig");
const c = @import("c.zig").c;
const handleHR = @import("hr.zig").handleHR;

/// Frame represents a single frame of a captured stream
/// Its inner resource is a GPU texture. Use Frame.Converter for accessing the data on the CPU.
const Frame = @This();

c_ptr: *c.IDXGIResource,
info: c.DXGI_OUTDUPL_FRAME_INFO,
duplication: DXGI.Output1.Duplication,
texture: *c.ID3D11Texture2D,

pub fn init(duplication: DXGI.Output1.Duplication) !Frame {
    var c_ptr: ?*c.IDXGIResource = null;
    var info: c.DXGI_OUTDUPL_FRAME_INFO = undefined;
    try handleHR(
        duplication.c_ptr.lpVtbl.*.AcquireNextFrame.?(
            duplication.c_ptr,
            1000,
            &info,
            @ptrCast(&c_ptr),
        ),
    );

    if (c_ptr == null) {
        return error.GetFrameFailed;
    }

    // Get the texture from the frame
    var texture: ?*c.ID3D11Texture2D = null;
    try handleHR(
        c_ptr.?.lpVtbl.*.QueryInterface.?(
            c_ptr.?,
            &c.IID_ID3D11Texture2D,
            @ptrCast(&texture),
        ),
    );

    return .{
        .c_ptr = c_ptr.?,
        .info = info,
        .duplication = duplication,
        .texture = texture.?,
    };
}

pub fn deinit(self: *Frame) void {
    _ = self.duplication.c_ptr.lpVtbl.*.ReleaseFrame.?(self.duplication.c_ptr);
    _ = self.texture.lpVtbl.*.Release.?(self.texture);
    _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
}

/// Converter moves frame pixels from the GPU to the CPU
pub const Converter = struct {
    staging_texture: Texture,
    d3d_device: D3D11.Device,
    width: u32,
    height: u32,

    pub fn init(d3d_device: D3D11.Device, width: u32, height: u32) !Converter {
        const staging_texture = try Texture.init(d3d_device, width, height);

        return Converter{
            .staging_texture = staging_texture,
            .d3d_device = d3d_device,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Converter) void {
        self.staging_texture.deinit();
    }

    pub fn requiredBufferSize(self: Converter) usize {
        return self.width * self.height * 4; // RGBA
    }

    pub fn getPixels(self: Converter, frame: *Frame, buffer: []u8) !void {
        if (buffer.len < self.requiredBufferSize()) {
            return error.BufferTooSmall;
        }

        // Copy from frame texture to our own staging texture
        try self.d3d_device.copyResource(
            @ptrCast(self.staging_texture.c_ptr),
            @ptrCast(frame.texture),
        );

        var mapped_resource: c.D3D11_MAPPED_SUBRESOURCE = undefined;
        try handleHR(self.d3d_device.ctx.lpVtbl.*.Map.?(
            self.d3d_device.ctx,
            @ptrCast(self.staging_texture.c_ptr),
            0,
            c.D3D11_MAP_READ,
            0,
            &mapped_resource,
        ));
        defer self.d3d_device.ctx.lpVtbl.*.Unmap.?(
            self.d3d_device.ctx,
            @ptrCast(self.staging_texture.c_ptr),
            0,
        );

        const pixels: [*]u8 = @ptrCast(mapped_resource.pData);
        const row_size = self.width * 4;

        var y: usize = 0;
        while (y < self.height) : (y += 1) {
            const src_offset = y * mapped_resource.RowPitch;
            const dst_offset = y * row_size;
            @memcpy(
                buffer[dst_offset .. dst_offset + row_size],
                pixels[src_offset .. src_offset + row_size],
            );
        }
    }
};

pub const Texture = struct {
    c_ptr: *c.ID3D11Texture2D, // an on-CPU 2d texture

    fn init(d3d_device: D3D11.Device, width: u32, height: u32) !Texture {
        const c_ptr = try d3d_device.newTexture(width, height);
        return .{
            .c_ptr = c_ptr,
        };
    }

    fn deinit(self: *Texture) void {
        _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
    }
};
