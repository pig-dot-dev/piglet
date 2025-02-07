const std = @import("std");
const websocket = @import("websocket");
const httpz = @import("httpz");
const json = std.json;
const http = std.http;

const MAX_BODY_SIZE = 1024 * 1024 * 10; // 10MB to match websocket max_size
const MAX_HEADERS_SIZE = 1024 * 64; // 64KB to match buffer_size

const Request = struct {
    requestId: []const u8,
    method: []const u8,
    path: []const u8,
    headers: json.ArrayHashMap([]const u8),
    body: ?[]const u8,
    query: []const u8,
};

const Response = struct {
    requestId: []const u8,
    status: u16,
    headers: ?json.ArrayHashMap([]const u8),
    body: ?[]const u8,
};

const Handler = struct {
    allocator: std.mem.Allocator,
    client: *websocket.Client,
    http_client: http.Client,
    target_port: u16,

    pub fn init(allocator: std.mem.Allocator, ws_client: *websocket.Client, target_port: u16) Handler {
        return .{
            .allocator = allocator,
            .client = ws_client,
            .http_client = http.Client{ .allocator = allocator },
            .target_port = target_port,
        };
    }

    pub fn deinit(self: *Handler) void {
        self.http_client.deinit();
    }

    pub fn handle(h: *Handler, message: websocket.Message) !void {
        // Websocket library expects us to implement this method within a Handler class
        switch (message.type) {
            .text => {
                const parsed = try std.json.parseFromSlice(Request, h.allocator, message.data, .{});
                defer parsed.deinit();
                const payload = parsed.value;
                try h.forwardRequest(payload);
            },
            else => {},
        }
    }

    fn forwardRequest(h: *Handler, payload: Request) !void {
        var headers_buf: [MAX_HEADERS_SIZE]u8 = undefined;

        const full_uri = try std.fmt.allocPrint(h.allocator, "http://localhost:{d}{s}?{s}", .{ h.target_port, payload.path, payload.query });
        defer h.allocator.free(full_uri);

        const uri = try std.Uri.parse(full_uri);
        var req = try h.http_client.open(.GET, uri, .{ .server_header_buffer = &headers_buf });
        defer req.deinit();
        try req.send();
        try req.finish();
        try req.wait();

        // Read response body
        var body_buf: [MAX_BODY_SIZE]u8 = undefined;
        _ = try req.readAll(&body_buf);
        const body_len = req.response.content_length orelse return error.NoBodyLength;

        // Reply back to the websocket server
        const response = Response{
            .requestId = payload.requestId,
            .status = @intCast(@intFromEnum(req.response.status)),
            .headers = null, // TODO: implement header return
            .body = body_buf[0..body_len],
        };
        var res_buf: [MAX_BODY_SIZE + MAX_HEADERS_SIZE + 1024]u8 = undefined; // 1024 for some extra space for stuff
        var fba = std.heap.FixedBufferAllocator.init(&res_buf);
        var string = std.ArrayList(u8).init(fba.allocator());
        defer string.deinit();
        try std.json.stringify(response, .{}, string.writer());
        return h.write(string.items);
    }

    pub fn write(self: *Handler, data: []u8) !void {
        return self.client.write(data);
    }

    pub fn close(self: *Handler) void {
        self.deinit();
    }
};

pub fn connectAndListen(allocator: std.mem.Allocator, server_host: []const u8, server_path: []const u8, server_port: u16, target_port: u16) !void {
    std.debug.print("Attempting to connect to wss://{s}:{d}{s}\n", .{ server_host, server_port, server_path });

    // Create a certificate bundle for TLS
    var bundle = std.crypto.Certificate.Bundle{};
    try bundle.rescan(allocator);
    defer {
        std.debug.print("Deinitializing certificate bundle\n", .{});
        bundle.deinit(allocator);
        std.debug.print("Deinitialized certificate bundle\n", .{});
    }

    var client = try websocket.connect(allocator, server_host, server_port, .{
        .tls = true,
        .ca_bundle = bundle,
        .max_size = 1024 * 1024 * 10, // 10MB max message size
        .buffer_size = 1024 * 64, // 64KB buffer size
    });
    defer client.deinit();

    const headers_str = try std.fmt.allocPrint(allocator, "Host: {s}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13", .{server_host});
    defer allocator.free(headers_str);

    std.debug.print("Connected, performing handshake with headers:\n{s}\n", .{headers_str});
    try client.handshake(server_path, .{
        .timeout_ms = 5000,
        .headers = headers_str,
    });
    std.debug.print("Handshake complete, creating handler\n", .{});

    var handler = Handler.init(allocator, &client, target_port);
    defer handler.deinit();

    std.debug.print("Starting message loop\n", .{});
    return try client.readLoop(&handler);
}
