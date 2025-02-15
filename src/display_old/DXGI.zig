const std = @import("std");
const win = std.os.windows;
const c = @import("c.zig").c;

const handleHR = @import("hr.zig").handleHR;
const D3D11 = @import("D3D11.zig");

pub const Device = struct {
    c_ptr: *c.IDXGIDevice,

    pub fn init(parent: D3D11.Device) !Device {
        return .{
            .c_ptr = try parent.queryInterface(c.IDXGIDevice, &c.IID_IDXGIDevice),
        };
    }

    pub fn getAdapter(self: Device) !*c.IDXGIAdapter {
        var adapter: ?*c.IDXGIAdapter = null;
        try handleHR(self.c_ptr.lpVtbl.*.GetAdapter.?(self.c_ptr, &adapter));
        if (adapter == null) return error.GetAdapterFailed;
        return adapter.?;
    }

    pub fn deinit(self: *Device) void {
        _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
    }
};

pub const Adapter = struct {
    c_ptr: *c.IDXGIAdapter,

    pub fn init(parent: Device) !Adapter {
        return .{
            .c_ptr = try parent.getAdapter(),
        };
    }

    pub fn getOutput(self: Adapter) !*c.IDXGIOutput {
        var output: ?*c.IDXGIOutput = null;
        // FUTURE TODO: in a server environment, there will be no outputs, because there are no displays.
        // We'd want to set up a Virtual Display Driver here if required.
        try handleHR(self.c_ptr.lpVtbl.*.EnumOutputs.?(self.c_ptr, 0, &output));
        if (output == null) return error.GetOutputFailed;
        return output.?;
    }

    pub fn deinit(self: *Adapter) void {
        _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
    }
};

pub const Output = struct {
    c_ptr: *c.IDXGIOutput,

    pub fn init(parent: Adapter) !Output {
        return .{
            .c_ptr = try parent.getOutput(),
        };
    }

    pub fn queryInterface(self: Output, comptime T: type, iid: *const c.GUID) !*T {
        var result: ?*T = null;
        try handleHR(self.c_ptr.lpVtbl.*.QueryInterface.?(self.c_ptr, iid, @ptrCast(&result)));
        if (result == null) return error.QueryInterfaceFailed;
        return result.?;
    }

    pub fn deinit(self: *Output) void {
        _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
    }

    pub const Dimensions = struct {
        width: u32,
        height: u32,
    };

    // Get dimensions from output description
    // NOTE you must first create Output1 before calling this function
    // Otherwise the dimensions are incorrect
    pub fn getDimensions(self: Output) !Dimensions {
        var desc: c.DXGI_OUTPUT_DESC = undefined;
        try handleHR(self.c_ptr.lpVtbl.*.GetDesc.?(self.c_ptr, &desc));

        var monitor_info: c.MONITORINFO = undefined;
        monitor_info.cbSize = @sizeOf(c.MONITORINFO);
        if (c.GetMonitorInfoW(desc.Monitor, &monitor_info) == 0) {
            return error.GetMonitorInfoFailed;
        }

        return .{
            .width = @intCast(monitor_info.rcMonitor.right - monitor_info.rcMonitor.left),
            .height = @intCast(monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top),
        };
    }
};

pub const Output1 = struct {
    c_ptr: *c.IDXGIOutput1,

    pub fn init(parent: Output) !Output1 {
        return .{
            .c_ptr = try parent.queryInterface(c.IDXGIOutput1, &c.IID_IDXGIOutput1),
        };
    }

    pub fn deinit(self: *Output1) void {
        _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
    }

    pub const Duplication = struct {
        c_ptr: *c.IDXGIOutputDuplication, // Matching the pattern from other structs

        pub fn init(output1: Output1, d3d_device: D3D11.Device) !Duplication {
            var duplication: ?*c.IDXGIOutputDuplication = null;
            try handleHR(output1.c_ptr.lpVtbl.*.DuplicateOutput.?(output1.c_ptr, @ptrCast(d3d_device.c_ptr), &duplication));
            if (duplication == null) return error.DuplicationFailed;

            return .{
                .c_ptr = duplication.?,
            };
        }

        pub fn deinit(self: *Duplication) void {
            _ = self.c_ptr.lpVtbl.*.Release.?(self.c_ptr);
        }
    };
};
