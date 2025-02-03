const std = @import("std");
const win = std.os.windows;

/// Windows functions return integer errors called HRESULTS.
/// This function wraps those into Zig errors.
pub fn handleHR(hr: c_int) !void {
    if (hr < 0) {
        const hr_u32 = @as(u32, @bitCast(hr));
        std.debug.print("HRESULT: 0x{x}\n", .{hr_u32});

        // Check ranges (search for error codes in c import shim)
        const facility = (hr_u32 >> 16) & 0x7FFF;
        switch (facility) {
            0x887A => {
                std.debug.print("DXGI Error\n", .{});
                return error.DXGIError;
            },
            0x887B => {
                std.debug.print("DXGI DDI Error\n", .{});
                return error.DXGIDDIError;
            },
            0x887C => {
                std.debug.print("D3D11 Error\n", .{});
                return error.D3D11Error;
            },
            else => {
                // If not a DirectX error, try Windows error codes
                const win_err = win.HRESULT_CODE(hr);
                std.debug.print("Windows error name: {s}\n", .{@tagName(win_err)});
                return error.UnknownWindowsError;
            },
        }
    }
}
