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
        // called automatically on close
        self.http_client.deinit();
    }

    pub fn handle(h: *Handler, message: websocket.Message) !void {
        // Websocket library expects us to implement this method within a Handler class
        switch (message.type) {
            .binary => {
                var arena = std.heap.ArenaAllocator.init(h.allocator);
                defer arena.deinit();
                const parsed = try std.json.parseFromSlice(Request, arena.allocator(), message.data, .{});
                const payload = parsed.value;
                h.forwardRequest(arena.allocator(), payload) catch |err| {
                    std.debug.print("Error forwarding request: {s}\n", .{@errorName(err)});
                    return err;
                };
            },
            else => {},
        }
    }

    fn forwardRequest(h: *Handler, arena_alloc: std.mem.Allocator, payload: Request) !void {
        var headers_buf: [MAX_HEADERS_SIZE]u8 = undefined;
        const full_uri = try std.fmt.allocPrint(arena_alloc, "http://localhost:{d}{s}?{s}", .{ h.target_port, payload.path, payload.query });

        const uri = try std.Uri.parse(full_uri);
        var req = try h.http_client.open(.GET, uri, .{ .server_header_buffer = &headers_buf });
        defer req.deinit();
        try req.send();
        try req.finish();
        try req.wait();

        // Read response body
        const content_length = req.response.content_length orelse return error.NoBodyLength;
        std.debug.print("Forwarding response of size: {d} bytes\n", .{content_length});

        var body_buf = try arena_alloc.alloc(u8, content_length);
        const body_len = try req.readAll(body_buf);
        std.debug.print("Read response of size: {d} bytes\n", .{body_len});

        // Reply back to the websocket server
        const response = Response{
            .requestId = payload.requestId,
            .status = @intCast(@intFromEnum(req.response.status)),
            .headers = null, // TODO: implement header return
            .body = body_buf[0..body_len],
        };

        var writer = std.ArrayList(u8).init(arena_alloc);
        try std.json.stringify(response, .{}, writer.writer());
        try h.client.writeBin(writer.items);
    }

    pub fn write(self: *Handler, data: []u8) !void {
        return self.client.write(data);
    }

    pub fn close(self: *Handler) void {
        // Websocket library expects us to implement this method within a Handler class
        self.deinit();
    }
};

pub const TunnelOptions = struct {
    control_host: []const u8,
    bearer_token: ?[]const u8 = null,
    control_port: u16 = 443,
    target_port: u16 = 3000,
};

/// Start a websocket client and subscribe to a control server
/// Forwarding requests to the local server
pub fn startControlTunnel(allocator: std.mem.Allocator, options: TunnelOptions) !void {
    const control_path = "/tunnel/ws";

    // Create a certificate bundle for TLS
    var bundle = std.crypto.Certificate.Bundle{};
    try bundle.rescan(allocator);
    defer bundle.deinit(allocator);

    // Sanitize server_host
    var host = options.control_host;

    // Strip leading http:// from server_host
    if (std.mem.startsWith(u8, host, "http://")) {
        host = host[7..];
    }
    // Strip leading https:// from host
    if (std.mem.startsWith(u8, host, "https://")) {
        host = host[8..];
    }
    // Strip trailing slash from host
    if (std.mem.endsWith(u8, host, "/")) {
        host = host[0 .. host.len - 1];
    }

    var client = try websocket.connect(allocator, host, options.control_port, .{
        .tls = true,
        .ca_bundle = bundle,
        .max_size = 1024 * 1024 * 10, // 10MB max message size
        .buffer_size = 1024 * 64, // 64KB buffer size
    });
    defer client.deinit();

    const headers_str = try std.fmt.allocPrint(allocator, "Host: {s}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13{s}", .{
        host,
        if (options.bearer_token) |token|
            try std.fmt.allocPrint(allocator, "\r\nAuthorization: Bearer {s}", .{token})
        else
            "",
    });
    defer allocator.free(headers_str);

    try client.handshake(control_path, .{
        .timeout_ms = 5000,
        .headers = headers_str,
    });

    var handler = Handler.init(allocator, &client, options.target_port);

    std.debug.print("Connected to control server\n", .{});
    return try client.readLoop(&handler);
}
