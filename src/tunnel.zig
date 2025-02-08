const std = @import("std");
const websocket = @import("websocket");
const httpz = @import("httpz");
const json = std.json;
const http = std.http;

const MAX_BODY_SIZE = 1024 * 1024 * 10; // 10MB to match websocket max_size
const MAX_HEADERS_SIZE = 1024 * 64; // 64KB to match buffer_size

const RequestMeta = struct {
    requestId: []const u8,
    method: []const u8,
    path: []const u8,
    headers: json.ArrayHashMap([]const u8),
    query: []const u8,
};

const ResponseMeta = struct {
    requestId: []const u8,
    status: u16,
    headers: ?json.ArrayHashMap([]const u8),
};
const RequestState = enum {
    awaiting_meta,
    awaiting_body,
};

const RequestAccumulator = struct {
    state: RequestState = .awaiting_meta,
    meta_parse_result: ?std.json.Parsed(RequestMeta) = null,
    body: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RequestAccumulator {
        return .{
            .state = .awaiting_meta,
            .meta_parse_result = null,
            .body = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RequestAccumulator) void {
        if (self.meta_parse_result) |*meta| {
            meta.deinit();
        }
        self.body.deinit(); // Frees underlying memory
    }

    pub fn reset(self: *RequestAccumulator) void {
        if (self.meta_parse_result) |*meta| {
            meta.deinit();
            self.meta_parse_result = null;
        }
        self.state = .awaiting_meta;
        self.body.clearRetainingCapacity(); // Keeps allocated memory for reuse
    }
};

const Handler = struct {
    allocator: std.mem.Allocator,
    client: *websocket.Client,
    http_client: http.Client,
    target_port: u16,
    accumulator: RequestAccumulator,

    pub fn init(allocator: std.mem.Allocator, ws_client: *websocket.Client, target_port: u16) Handler {
        return .{
            .allocator = allocator,
            .client = ws_client,
            .http_client = http.Client{ .allocator = allocator },
            .target_port = target_port,
            .accumulator = RequestAccumulator.init(allocator),
        };
    }

    pub fn deinit(self: *Handler) void {
        self.http_client.deinit();
        self.accumulator.deinit();
    }

    pub fn handle(h: *Handler, message: websocket.Message) !void {
        switch (h.accumulator.state) {
            .awaiting_meta => {
                if (message.type != .text) return error.ExpectedMetadata;
                const parse_result = try std.json.parseFromSlice(RequestMeta, h.allocator, message.data, .{});
                h.accumulator.meta_parse_result = parse_result;
                h.accumulator.state = .awaiting_body;
            },
            .awaiting_body => {
                if (message.type == .text) {
                    if (std.mem.eql(u8, message.data, "end")) {
                        // text message "end" is sent to mark the end of a request body
                        defer h.accumulator.reset();
                        try h.forwardRequest();
                    } else {
                        return error.UnexpectedTextMessage;
                    }
                } else if (message.type == .binary) {
                    try h.accumulator.body.appendSlice(message.data);
                } else {
                    return error.UnexpectedMessageType;
                }
            },
        }
    }
    fn forwardRequest(h: *Handler) !void {
        var arena = std.heap.ArenaAllocator.init(h.allocator);
        defer arena.deinit();
        var allocator = arena.allocator();

        const meta_result = h.accumulator.meta_parse_result orelse return error.NoMetadata;
        const meta = meta_result.value;

        // Start building our http request

        var headers_buf: [MAX_HEADERS_SIZE]u8 = undefined;
        const full_uri = try std.fmt.allocPrint(allocator, "http://localhost:{d}{s}?{s}", .{
            h.target_port,
            meta.path,
            meta.query,
        });

        const uri = try std.Uri.parse(full_uri);
        const method = std.meta.stringToEnum(http.Method, meta.method) orelse return error.InvalidMethod;

        var req = try h.http_client.open(method, uri, .{ .server_header_buffer = &headers_buf });
        defer req.deinit();

        // TODO: Set headers from meta

        // Send body if we have one
        try req.send();
        if (h.accumulator.body.items.len > 0) {
            std.debug.print("Forwarding request body: {d} bytes\n", .{h.accumulator.body.items.len});
            try req.writeAll(h.accumulator.body.items);
        }
        try req.finish();
        try req.wait();

        // Start building our websocket responses

        // Send response meta as JSON
        const response_meta = ResponseMeta{
            .requestId = meta.requestId,
            .status = @intCast(@intFromEnum(req.response.status)),
            .headers = null,
        };
        var json_writer = std.ArrayList(u8).init(allocator);
        try std.json.stringify(response_meta, .{}, json_writer.writer());
        std.debug.print("Returning response meta: {s}\n", .{json_writer.items});
        try h.client.write(json_writer.items);
        std.debug.print("Done returning response meta\n", .{});

        // Send response body if we have one
        if (req.response.content_length) |content_length| {
            var body_buf = try allocator.alloc(u8, content_length);
            const body_len = try req.readAll(body_buf);
            std.debug.print("Returning body of size: {d} bytes\n", .{body_len});

            // Send in chunks
            const CHUNK_SIZE = 16 * 1024; // 16KB chunks
            if (body_len > 0) {
                var offset: usize = 0;
                while (offset < body_len) {
                    const remaining = body_len - offset;
                    const chunk_size = @min(CHUNK_SIZE, remaining);
                    std.debug.print("Returning chunk of size: {d} bytes\n", .{chunk_size});
                    try h.client.writeBin(body_buf[offset .. offset + chunk_size]);
                    offset += chunk_size;
                }
            }
        }

        // Send end signal
        var end_msg = [_]u8{ 'e', 'n', 'd' };
        try h.client.write(&end_msg);
    }

    pub fn close(self: *Handler) void {
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
