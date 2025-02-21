const std = @import("std");

const c = @cImport({
    // Workarounds to make ZLS work when run from MacOS
    @cDefine("_WIN32", "1");
    @cDefine("__MINGW32__", "1");
    @cDefine("__declspec(x)", "");

    // Includes
    @cInclude("windows.h");
});

// Embed the cursor bitmap
const CURSOR_BITMAP_DATA = @embedFile("assets/pink_cursor.bmp");

pub fn startOverlay(allocator: std.mem.Allocator) !void {
    // start cursor overlay
    var window = try CursorOverlay.init(allocator);
    window.show();
    window.run();
}

pub const CursorOverlay = struct {
    hwnd: c.HWND,
    instance: c.HINSTANCE,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub const Config = struct {
        // RGB values for Pig Peach
        pub const color_r: u8 = 0xFF;
        pub const color_g: u8 = 0x00;
        pub const color_b: u8 = 0xE5;
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        // Get current app instance
        const instance: c.HINSTANCE = @ptrCast(c.GetModuleHandleW(null));
        if (instance == null) return error.ModuleHandleFailed;

        // Tell windows we're creating a window
        try registerWindowClass(allocator, instance);
        const hwnd = try createWindow(allocator, instance);

        return Self{
            .hwnd = hwnd,
            .instance = instance,
            .allocator = allocator,
        };
    }

    pub fn show(self: *Self) void {
        _ = c.ShowWindow(self.hwnd, c.SW_SHOW);
        self.updateWindow();
    }

    fn updateWindow(self: *Self) void {
        // Get the screen dimensions
        const screen_width = c.GetSystemMetrics(c.SM_CXSCREEN);
        const screen_height = c.GetSystemMetrics(c.SM_CYSCREEN);

        // Create a DC for the new window
        const hdcScreen = c.GetDC(null);
        const hdcMem = c.CreateCompatibleDC(hdcScreen);
        defer _ = c.DeleteDC(hdcMem);
        defer _ = c.ReleaseDC(null, hdcScreen);

        // Create a bitmap for the window contents
        var bi = c.BITMAPINFO{
            .bmiHeader = .{
                .biSize = @sizeOf(c.BITMAPINFOHEADER),
                .biWidth = screen_width,
                .biHeight = -screen_height, // Negative for top-down
                .biPlanes = 1,
                .biBitCount = 32,
                .biCompression = c.BI_RGB,
                .biSizeImage = 0,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed = 0,
                .biClrImportant = 0,
            },
            .bmiColors = undefined,
        };

        var bits: ?*anyopaque = null;
        const hbmp = c.CreateDIBSection(hdcMem, &bi, c.DIB_RGB_COLORS, &bits, null, 0);
        defer _ = c.DeleteObject(hbmp);

        if (bits) |ptr| {
            // Initialize bitmap to transparent
            const pixels = @as([*]u32, @ptrCast(@alignCast(ptr)));
            const total_pixels = @as(usize, @intCast(screen_width * screen_height));
            for (0..total_pixels) |i| {
                pixels[i] = 0; // All pixels transparent
            }

            // Get cursor position
            var cursor: c.POINT = undefined;
            if (c.GetCursorPos(&cursor) == 0) {
                return;
            }

            // Skip past BMP headers (54 bytes) to get to pixel data
            const pixel_data = CURSOR_BITMAP_DATA[54..];

            // Debug print BMP header info
            const bmp_header = CURSOR_BITMAP_DATA[0..54];
            const width = @as(i32, @bitCast(std.mem.readInt(u32, bmp_header[18..22], .little)));
            const height = @as(i32, @bitCast(std.mem.readInt(u32, bmp_header[22..26], .little)));
            const bits_per_pixel = std.mem.readInt(u16, bmp_header[28..30], .little);
            const compression = std.mem.readInt(u32, bmp_header[30..34], .little);
            
            // Print header info
            std.debug.print("BMP Header: width={}, height={}, bpp={}, compression={}\n", .{
                width, height, bits_per_pixel, compression
            });
            
            // Print first 8 pixels to see the pattern
            std.debug.print("First 8 pixels:\n", .{});
            var i: usize = 0;
            while (i < 32) : (i += 4) {
                std.debug.print("Pixel {}: [{x:0>2}, {x:0>2}, {x:0>2}, {x:0>2}]\n", .{
                    i/4,
                    pixel_data[i],
                    pixel_data[i + 1],
                    pixel_data[i + 2],
                    pixel_data[i + 3],
                });
            }
            
            // Calculate row stride including padding
            const unpadded_row_size = width * 4;  // 4 bytes per pixel for 32bpp
            const padding = (4 - (unpadded_row_size % 4)) % 4;  // Padding to make row size multiple of 4
            const row_stride = unpadded_row_size + padding;
            
            std.debug.print("BMP Info: width={}, height={}, bpp={}, stride={}\n", .{
                width, height, bits_per_pixel, row_stride
            });

            // Copy pixel data directly
            var y: c_int = 0;
            while (y < height) : (y += 1) {
                var x: c_int = 0;
                while (x < width) : (x += 1) {
                    const src_idx: usize = @intCast(((height - 1 - y) * row_stride + x * 4));
                    
                    if (src_idx + 3 < pixel_data.len) {
                        const screen_x = x + cursor.x;
                        const screen_y = y + cursor.y;

                        if (screen_x >= 0 and screen_x < screen_width and
                            screen_y >= 0 and screen_y < screen_height)
                        {
                            // BMP stores colors as BGR, we need RGBA
                            const b = pixel_data[src_idx];
                            const g = pixel_data[src_idx + 1];
                            const r = pixel_data[src_idx + 2];
                            const a = pixel_data[src_idx + 3];

                            const color = (@as(u32, a) << 24) | // Alpha in most significant byte
                                (@as(u32, r) << 16) | // Red
                                (@as(u32, g) << 8) | // Green
                                @as(u32, b); // Blue

                            const dest_idx = @as(usize, @intCast(screen_y * screen_width + screen_x));
                            pixels[dest_idx] = color;
                        }
                    }
                }
            }
        }

        _ = c.SelectObject(hdcMem, hbmp);

        // Set up the layered window update parameters
        var blend: c.BLENDFUNCTION = .{
            .BlendOp = c.AC_SRC_OVER,
            .BlendFlags = 0,
            .SourceConstantAlpha = 255,
            .AlphaFormat = c.AC_SRC_ALPHA,
        };

        var point = c.POINT{ .x = 0, .y = 0 };
        var size = c.SIZE{
            .cx = screen_width,
            .cy = screen_height,
        };

        _ = c.UpdateLayeredWindow(
            self.hwnd,
            hdcScreen,
            null,
            &size,
            hdcMem,
            &point,
            0,
            &blend,
            c.ULW_ALPHA,
        );
    }

    // Run is the blocking "server" that'll dispatch OS signals onward to WindowProc
    pub fn run(self: *Self) void {
        var msg: c.MSG = undefined;

        // Create a timer for regular updates (16ms = ~60fps)
        const timer_id = 1;
        _ = c.SetTimer(self.hwnd, timer_id, 16, null);

        while (c.GetMessageW(&msg, null, 0, 0) != 0) {
            switch (msg.message) {
                c.WM_TIMER => {
                    // it's our timer for window updates
                    if (msg.wParam == timer_id) {
                        self.updateWindow();
                    }
                },
                else => {
                    // forward onward to WindowProc
                    _ = c.TranslateMessage(&msg);
                    _ = c.DispatchMessageW(&msg);
                },
            }
        }

        // Cleanup timer
        _ = c.KillTimer(self.hwnd, timer_id);
    }

    /// Tells the Windows OS we're creating a window
    fn registerWindowClass(allocator: std.mem.Allocator, instance: c.HINSTANCE) !void {
        const class_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "Transparent Window Class");
        var wc = c.WNDCLASSEXW{
            .cbSize = @sizeOf(c.WNDCLASSEXW),
            .style = 0,
            .lpfnWndProc = WindowProc, // Register a handler for OS signals like close
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = instance,
            .hIcon = null,
            .hCursor = c.LoadCursorW(null, @ptrFromInt(32512)), // 32512 is IDC_ARROW
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = class_name.ptr,
            .hIconSm = null,
        };

        if (c.RegisterClassExW(&wc) == 0) {
            return error.WindowClassRegistrationFailed;
        }
    }

    /// Actually creates the window, styles it, etc
    fn createWindow(allocator: std.mem.Allocator, instance: c.HINSTANCE) !c.HWND {
        const class_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "Transparent Window Class");
        const window_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "Piglet Cursor Overlay");

        const hwnd = c.CreateWindowExW(
            c.WS_EX_LAYERED | c.WS_EX_TOPMOST | c.WS_EX_TRANSPARENT |
                c.WS_EX_NOACTIVATE |
                c.WS_EX_TOOLWINDOW,
            class_name.ptr,
            window_name.ptr,
            c.WS_POPUP,
            0,
            0,
            c.GetSystemMetrics(c.SM_CXSCREEN),
            c.GetSystemMetrics(c.SM_CYSCREEN),
            null,
            null,
            instance,
            null,
        );

        if (hwnd == null) return error.WindowCreationFailed;
        return hwnd;
    }
};

// WindowProc is a handler for OS signals
// we just use it to handle the most basic case: window destroys
export fn WindowProc(hwnd: c.HWND, uMsg: c.UINT, wParam: c.WPARAM, lParam: c.LPARAM) c.LRESULT {
    switch (uMsg) {
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        c.WM_TIMER => return 0, // Handle timer messages
        else => return c.DefWindowProcW(hwnd, uMsg, wParam, lParam),
    }
}
