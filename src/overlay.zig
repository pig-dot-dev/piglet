const std = @import("std");

const c = @cImport({
    // Workarounds to make ZLS work when run from MacOS
    @cDefine("_WIN32", "1");
    @cDefine("__MINGW32__", "1");
    @cDefine("__declspec(x)", "");

    // Includes
    @cInclude("windows.h");
});

pub fn startOverlay() !void {
    // start cursor overlay
    var window = try CursorOverlay.init();
    window.show();
    window.run();
}

pub const CursorOverlay = struct {
    hwnd: c.HWND,
    instance: c.HINSTANCE,

    const Self = @This();

    pub const Config = struct {
        // RGB values for Pig Peach
        pub const color_r: u8 = 0xFF;
        pub const color_g: u8 = 0x00;
        pub const color_b: u8 = 0xE5;
    };

    pub fn init() !Self {
        // Get current app instance
        const instance: c.HINSTANCE = @ptrCast(c.GetModuleHandleW(null));
        if (instance == null) return error.ModuleHandleFailed;

        // Tell windows we're creating a window
        try registerWindowClass(instance);
        const hwnd = try createWindow(instance);

        return Self{
            .hwnd = hwnd,
            .instance = instance,
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

        // Initialize bitmap to transparent
        if (bits) |ptr| {
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

            // Draw filled circle with alpha
            const radius: i32 = 10;
            const alpha: u32 = 180; // Opacity (0-255)
            // Pre-multiply RGB values with alpha
            const color = (alpha << 24) | // Alpha in most significant byte
                ((Config.color_b * alpha / 255) << 16) | // Pre-multiplied Blue
                ((Config.color_g * alpha / 255) << 8) | // Pre-multiplied Green
                (Config.color_r * alpha / 255); // Pre-multiplied Red

            // Calculate bounding box for the circle
            const min_x = @max(0, cursor.x - radius);
            const max_x = @min(cursor.x + radius, screen_width - 1);
            const min_y = @max(0, cursor.y - radius);
            const max_y = @min(cursor.y + radius, screen_height - 1);

            // Fill circle pixels (only within bounding box)
            var y: i32 = min_y;
            while (y <= max_y) : (y += 1) {
                var x: i32 = min_x;
                while (x <= max_x) : (x += 1) {
                    const dx = x - cursor.x;
                    const dy = y - cursor.y;
                    if (dx * dx + dy * dy <= radius * radius) {
                        pixels[@intCast(y * screen_width + x)] = color;
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
    fn registerWindowClass(instance: c.HINSTANCE) !void {
        const class_name = L("Transparent Window Class");
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
            .lpszClassName = class_name,
            .hIconSm = null,
        };

        if (c.RegisterClassExW(&wc) == 0) {
            return error.WindowClassRegistrationFailed;
        }
    }

    /// Actually creates the window, styles it, etc
    fn createWindow(instance: c.HINSTANCE) !c.HWND {
        const hwnd = c.CreateWindowExW(
            c.WS_EX_LAYERED | c.WS_EX_TOPMOST | c.WS_EX_TRANSPARENT |
                c.WS_EX_NOACTIVATE |
                c.WS_EX_TOOLWINDOW,
            L("Transparent Window Class"),
            L("Piglet Cursor Overlay"),
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

// Helper for wide strings - fixed alignment issue
fn L(str: []const u8) [*:0]const u16 {
    const len = str.len;
    // Add 1 for null terminator
    const buffer: [*]u16 = @ptrCast(@alignCast(std.heap.page_allocator.alloc(u8, (len + 1) * 2) catch unreachable));

    var i: usize = 0;
    while (i < len) : (i += 1) {
        buffer[i] = @intCast(str[i]);
    }
    buffer[len] = 0;

    return buffer[0..len :0];
}
