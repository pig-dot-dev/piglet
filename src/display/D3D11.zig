const std = @import("std");
const win = std.os.windows;
const c = @import("c.zig").c;

const handleHR = @import("hr.zig").handleHR;

pub const Device = struct {
    c_ptr: *c.ID3D11Device,
    ctx: *c.ID3D11DeviceContext,

    pub fn init() !Device {
        var c_ptr: ?*c.ID3D11Device = null;
        var ctx: ?*c.ID3D11DeviceContext = null;

        try handleHR(
            // https://github.com/apitrace/dxsdk/blob/d964b66467aaa734edbc24326da8119f5f063dd3/Include/d3d11.h#L14413
            c.D3D11CreateDevice(
                null, // pAdapter, if null, use default adapter.
                c.D3D_DRIVER_TYPE_HARDWARE, // driver type
                null, // Software rasterizer, use null for hardware
                0, // flags, see D3D11CreateDeviceAndSwapChain.
                null, // pFeatureLevels, see D3D11CreateDeviceAndSwapChain
                0, // size of pFeatureLevels array
                c.D3D11_SDK_VERSION, // "use the D3D11_SDK_VERSION macro"
                &c_ptr, // ppDevice pointer to returned device
                null, // pointer to returned feature level.
                &ctx, // pointer to returned context
            ),
        );

        if (c_ptr == null or ctx == null) {
            return error.D3D11DeviceCreationFailed;
        }
        return .{
            .c_ptr = c_ptr.?,
            .ctx = ctx.?,
        };
    }

    pub fn queryInterface(self: Device, comptime T: type, iid: *const c.GUID) !*T {
        var result: ?*T = null;
        try handleHR(self.c_ptr.lpVtbl.*.QueryInterface.?(self.c_ptr, iid, @ptrCast(&result)));
        if (result == null) return error.QueryInterfaceFailed;
        return result.?;
    }

    pub fn copyResource(self: Device, dst: *c.ID3D11Resource, src: *c.ID3D11Resource) !void {
        self.ctx.lpVtbl.*.CopyResource.?(self.ctx, dst, src);
    }

    pub fn newTexture(self: Device, width: u32, height: u32) !*c.ID3D11Texture2D {
        // Create staging texture for CPU access
        var desc = c.D3D11_TEXTURE2D_DESC{
            .Width = width,
            .Height = height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = c.DXGI_FORMAT_B8G8R8A8_UNORM,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = c.D3D11_USAGE_STAGING,
            .BindFlags = 0,
            .CPUAccessFlags = c.D3D11_CPU_ACCESS_READ,
            .MiscFlags = 0,
        };

        var staging_texture: ?*c.ID3D11Texture2D = null;
        try handleHR(self.c_ptr.lpVtbl.*.CreateTexture2D.?(
            self.c_ptr,
            &desc,
            null,
            &staging_texture,
        ));
        if (staging_texture == null) return error.CreateTexture2DFailed;

        return staging_texture.?;
    }

    pub fn deinit(self: *Device) void {
        self.ctx.*.lpVtbl.*.Flush.?(self.ctx);
        self.ctx.*.lpVtbl.*.ClearState.?(self.ctx);
        _ = self.ctx.*.lpVtbl.*.Release.?(self.ctx);

        _ = self.c_ptr.*.lpVtbl.*.Release.?(self.c_ptr);
    }
};
