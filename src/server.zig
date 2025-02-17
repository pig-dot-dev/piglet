const std = @import("std");
const Computer = @import("Computer.zig");
const MouseButton = @import("input/Mouse.zig").Button;
const Coordinates = @import("input/Mouse.zig").Coordinates;
const httpz = @import("httpz"); // Note we use the version pinned to zig 0.13

const Deps = struct {
    computer: *Computer,
};

pub fn run(allocator: std.mem.Allocator, computer: *Computer, port: u16) !void {
    var app = Deps{ .computer = computer };

    // Pass Deps into ServerApp makes that pointer available in the handler
    // Useful for DB, config, a
    var server = try httpz.ServerApp(*Deps)
        .init(
        allocator,
        .{ .port = port },
        &app,
    );
    defer {
        // clean shutdown, finishes serving any live request
        server.stop();
        server.deinit();
    }

    var router = server.router();

    // Display endpoints
    router.get("/computer/display/screenshot", getScreenshot);
    router.get("/computer/display/dimensions", getDimensions);

    // Input endpoints
    // Keyboard
    router.post("/computer/input/keyboard/type", postKeyboardType); // body: { text: string }
    router.post("/computer/input/keyboard/key", postKeyboardKey); // body: { key: string }

    // Mouse
    router.get("/computer/input/mouse/position", getMousePosition);
    router.post("/computer/input/mouse/move", postMouseMove); // body: { x: number, y: number }
    router.post("/computer/input/mouse/click", postMouseClick); // body: { button?: "left"|"right" }

    // File system endpoints
    router.get("/computer/fs/list", getFsList); // query: { path: string }
    router.get("/computer/fs/read", getFsRead); // query: { path: string }
    router.post("/computer/fs/write", postFsWrite); // body: { path: string, content: string }
    // router.ws("/computer/fs/watch", null); // query: { path: string } // TODO: Figure out websockets

    // Shell endpoints
    // Sync commands
    router.post("/computer/shell/cmd/exec", postHandleCMDExec); // body: { command: string }
    router.post("/computer/shell/powershell/exec", postHandlePowerShellExec); // body: { command: string }

    // Interactive sessions via websocket // TODO: Figure out websockets
    // router.ws("/computer/shell/cmd/session", handleCmdSession);
    // router.ws("/computer/shell/powershell/session", handlePsSession);

    // blocks
    std.debug.print("Local server running at http://localhost:{d}\n", .{port});
    try server.listen();
}

fn notImplemented(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    try res.json(.{}, .{});
}

fn getScreenshot(deps: *Deps, _: *httpz.Request, res: *httpz.Response) !void {
    // todo: allow specifying size and format
    const image = try deps.computer.display.screenshot(res.arena, .{
        .width = 1024,
        .height = 768,
        .mode = .AspectFill, // means display will be correct scale, likely bigger than 1024x768
    });
    res.status = 200;
    res.header("Content-Type", "image/png");
    try res.writer().writeAll(image.bytes);
}

fn getDimensions(deps: *Deps, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    try res.json(.{
        .width = deps.computer.display.width(),
        .height = deps.computer.display.height(),
    }, .{});
}

const KeyboardPayload = struct { text: []const u8 };

fn postKeyboardType(deps: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    const body = try req.json(KeyboardPayload) orelse {
        res.status = 400;
        try res.json(.{}, .{});
        return;
    };
    try deps.computer.keyboard.inputString(body.text);
}

fn postKeyboardKey(deps: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    const body = try req.json(KeyboardPayload);
    if (body == null) {
        res.status = 400;
        try res.json(.{}, .{});
        return;
    }
    try deps.computer.keyboard.inputXDO(body.?.text);
}

fn getMousePosition(deps: *Deps, _: *httpz.Request, res: *httpz.Response) !void {
    const coordinates = try deps.computer.mouse.coordinates();
    res.status = 200;
    try res.json(.{
        .x = coordinates.x,
        .y = coordinates.y,
    }, .{});
}

const MouseMovePayload = struct { x: i32, y: i32 };
const ButtonEnum = enum {
    left,
    right,
};
const MouseClickPayload = struct { x: ?i32 = null, y: ?i32 = null, button: ButtonEnum, down: bool };

fn postMouseMove(deps: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    const body = try req.json(MouseMovePayload) orelse {
        res.status = 400;
        try res.json(.{}, .{});
        return;
    };
    try deps.computer.mouse.move(.{ .x = body.x, .y = body.y });
}

fn postMouseClick(deps: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    const body = try req.json(MouseClickPayload) orelse {
        res.status = 400;
        try res.json(.{}, .{});
        return;
    };

    // If x,y not provided, use current position
    const target: Coordinates = if (body.x != null and body.y != null)
        .{ .x = body.x.?, .y = body.y.? }
    else
        try deps.computer.mouse.coordinates();

    // map public mouse enum API to our internal one
    const button: MouseButton = switch (body.button) {
        .left => MouseButton.left,
        .right => MouseButton.right,
    };
    try deps.computer.mouse.click(button, body.down, target);
}

fn getFsList(_: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    try notImplemented(req, res);
}

fn getFsRead(_: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    try notImplemented(req, res);
}

fn postFsWrite(_: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    try notImplemented(req, res);
}

fn postHandleCMDExec(_: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    try notImplemented(req, res);
}

fn postHandlePowerShellExec(_: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    try notImplemented(req, res);
}
