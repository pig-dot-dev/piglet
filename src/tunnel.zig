const std = @import("std");
const websocket = @import("websocket");
const getConfig = @import("config.zig").getConfig;
const httpz = @import("httpz");
const json = std.json;
const http = std.http;

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

const RequestBuffer = struct {
    state: RequestState = .awaiting_meta,
    meta_parse_result: ?std.json.Parsed(RequestMeta) = null,
    body: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RequestBuffer {
        return .{
            .state = .awaiting_meta,
            .meta_parse_result = null,
            .body = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RequestBuffer) void {
        if (self.meta_parse_result) |*meta| {
            meta.deinit();
        }
        self.body.deinit(); // Frees underlying memory
    }

    pub fn reset(self: *RequestBuffer) void {
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

    request_buffer: RequestBuffer,

    pub fn init(allocator: std.mem.Allocator, ws_client: *websocket.Client, target_port: u16) Handler {
        return .{
            .allocator = allocator,
            .client = ws_client,
            .http_client = http.Client{ .allocator = allocator },
            .target_port = target_port,
            .request_buffer = RequestBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *Handler) void {
        self.http_client.deinit();
        self.request_buffer.deinit();
    }

    /// handle is the mandatory function interface for websocket library
    pub fn handle(h: *Handler, message: websocket.Message) !void {
        // handle:
        // 1. Decodes the websocket messages received from the tunnel
        // 2. Adds them to the request_buffer
        // 3. Triggers forwarding when the request is ready

        // Note this currently assumes one request at a time
        switch (h.request_buffer.state) {
            .awaiting_meta => {
                if (message.type != .text) return error.ExpectedMetadata;
                const parse_result = try std.json.parseFromSlice(RequestMeta, h.allocator, message.data, .{});
                h.request_buffer.meta_parse_result = parse_result;
                h.request_buffer.state = .awaiting_body;
            },
            .awaiting_body => {
                if (message.type == .text) {
                    // text message "end" is sent to mark the end of a request body
                    if (std.mem.eql(u8, message.data, "end")) {
                        defer h.request_buffer.reset(); // Frees up the accumulator for the next request
                        try h.forwardRequest();
                    } else {
                        return error.UnexpectedTextMessage;
                    }
                } else if (message.type == .binary) {
                    // binary messages are body chunks
                    try h.request_buffer.body.appendSlice(message.data);
                } else {
                    return error.UnexpectedMessageType;
                }
            },
        }
    }

    fn forwardRequest(h: *Handler) !void {
        // forwardRequest:
        // 1. Sends the request to the localhost server over http
        // 2. Receives the response over http
        // 3. Encodes that response as websoket messages and sends them up the tunnel

        var arena = std.heap.ArenaAllocator.init(h.allocator);
        defer arena.deinit();
        var allocator = arena.allocator();

        const meta_result = h.request_buffer.meta_parse_result orelse return error.NoMetadata;
        const meta = meta_result.value;

        // Build http request
        var headers_buf: [MAX_HEADERS_SIZE]u8 = undefined;
        const full_uri = try std.fmt.allocPrint(allocator, "http://localhost:{d}{s}?{s}", .{
            h.target_port,
            meta.path,
            meta.query,
        });

        const uri = try std.Uri.parse(full_uri);
        const method = std.meta.stringToEnum(http.Method, meta.method) orelse return error.InvalidMethod;

        // Start http request
        var req = try h.http_client.open(method, uri, .{ .server_header_buffer = &headers_buf });
        defer req.deinit();

        // TODO: Set headers from meta

        // Send body if we have one
        try req.send();
        if (h.request_buffer.body.items.len > 0) {
            std.debug.print("Forwarding request body: {d} bytes\n", .{h.request_buffer.body.items.len});
            try req.writeAll(h.request_buffer.body.items);
        }
        try req.finish();
        try req.wait();

        // Start building our websocket responses

        // Response meta sends up tunnel as json string
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

        // Body sends up tunnel as a sequence of binary messages
        if (req.response.content_length) |content_length| {
            var body_buf = try allocator.alloc(u8, content_length);
            const body_len = try req.readAll(body_buf);
            std.debug.print("Returning body of size: {d} bytes\n", .{body_len});

            // Send in chunks
            // this 16kb limit was a day-long bug to figure out
            // the websocket library seems to send an "unexpeted EOF" if chunks are too big
            // perhaps it has a buffer limit? despite me setting a huge buffer.
            // surely will be improved over time.
            const CHUNK_SIZE = 16 * 1024;
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

        // End signal marks the end of the response
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

    var config = try getConfig(allocator);
    defer config.deinit(allocator);

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
        .buffer_size = 1024 * 256, // 256KB buffer size
    });
    defer client.deinit();

    const headers_str = try std.fmt.allocPrint(allocator, "Host: {s}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13{s}\r\nX-PIGLET-FINGERPRINT: {s}\r\nX-PIGLET-VERSION: {s}\r\n", .{
        host,
        if (options.bearer_token) |token|
            try std.fmt.allocPrint(allocator, "\r\nAuthorization: Bearer {s}", .{token})
        else
            "",
        config.fingerprint,
        config.version,
    });
    std.debug.print("Headers: {s}\n", .{headers_str});
    defer allocator.free(headers_str);

    try client.handshake(control_path, .{
        .timeout_ms = 5000,
        .headers = headers_str,
    });

    var handler = Handler.init(allocator, &client, options.target_port);

    std.debug.print("Connected to control server\n", .{});
    return try client.readLoop(&handler);
}
