// wrapper around ffmpeg

const std = @import("std");

// FFmpeg C API bindings
const c = @cImport({
    // Workarounds to make ZLS work when run from MacOS
    @cDefine("_WIN32", "1");
    @cDefine("__MINGW32__", "1");
    @cDefine("__declspec(x)", "");
    @cDefine("__attribute__(x)", "");

    // FFmpeg headers
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavdevice/avdevice.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libavutil/imgutils.h");
});

const VideoContext = struct {
    input_ctx: ?*c.AVFormatContext,
    decoder_ctx: ?*c.AVCodecContext,
    video_stream_index: c_uint,

    pub fn init() !VideoContext {
        // Initialize device registry (needed for screen capture)
        c.avdevice_register_all();

        // Input format context for screen capture
        var input_ctx: ?*c.AVFormatContext = null;

        // Set up screen capture options
        var options: ?*c.AVDictionary = null;
        // Let gdigrab automatically detect screen dimensions
        _ = c.av_dict_set(&options, "framerate", "30", 0);

        // Open the screen capture device
        const input_format = c.av_find_input_format("gdigrab");
        if (input_format == null) {
            return error.GdigrabNotFound;
        }

        // Open input (screen capture)
        const ret = c.avformat_open_input(
            &input_ctx,
            "desktop", // Capture entire desktop
            input_format,
            &options,
        );
        if (ret < 0) {
            return error.FailedToOpenInput;
        }
        errdefer c.avformat_close_input(&input_ctx);

        // Get stream information
        if (c.avformat_find_stream_info(input_ctx, null) < 0) {
            return error.StreamInfoNotFound;
        }

        // Find the first video stream
        const video_stream_index = blk: {
            var i: c_uint = 0;
            while (i < input_ctx.?.nb_streams) : (i += 1) {
                const stream = input_ctx.?.streams[i].*;
                if (stream.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
                    break :blk i;
                }
            }
            return error.VideoStreamNotFound;
        };

        // Get the input stream and its parameters
        const input_stream = input_ctx.?.streams[video_stream_index].*;
        const codecpar = input_stream.codecpar;

        // Find decoder for the stream
        const decoder = c.avcodec_find_decoder(codecpar.*.codec_id);
        if (decoder == null) {
            return error.DecoderNotFound;
        }

        // Create decoder context
        var decoder_ctx = c.avcodec_alloc_context3(decoder);
        if (decoder_ctx == null) {
            return error.DecoderContextAllocationFailed;
        }
        errdefer c.avcodec_free_context(&decoder_ctx);

        // Fill decoder context with stream parameters
        if (c.avcodec_parameters_to_context(decoder_ctx, codecpar) < 0) {
            return error.DecoderParametersCopyFailed;
        }

        // Initialize decoder
        if (c.avcodec_open2(decoder_ctx, decoder, null) < 0) {
            return error.DecoderOpenFailed;
        }

        return VideoContext{
            .input_ctx = input_ctx,
            .decoder_ctx = decoder_ctx,
            .video_stream_index = video_stream_index,
        };
    }

    pub fn deinit(self: *VideoContext) void {
        if (self.decoder_ctx != null) {
            c.avcodec_free_context(&self.decoder_ctx);
        }
        if (self.input_ctx != null) {
            c.avformat_close_input(&self.input_ctx);
        }
    }

    pub fn captureFrame(self: *VideoContext) ![*c]c.AVFrame {
        var frame = c.av_frame_alloc();
        if (frame == null) {
            return error.FrameAllocationFailed;
        }
        errdefer c.av_frame_free(&frame);

        // Read one frame
        var packet: c.AVPacket = undefined;
        while (true) {
            const read_ret = c.av_read_frame(self.input_ctx, &packet);
            if (read_ret < 0) {
                return error.FrameReadFailed;
            }
            defer c.av_packet_unref(&packet);

            if (packet.stream_index == self.video_stream_index) {
                // Decode input packet to frame
                if (c.avcodec_send_packet(self.decoder_ctx, &packet) < 0) {
                    return error.PacketDecodingFailed;
                }
                if (c.avcodec_receive_frame(self.decoder_ctx, frame) < 0) {
                    return error.FrameDecodingFailed;
                }
                return frame;
            }
        }
    }
};

pub fn screenshot_to_png(allocator: std.mem.Allocator, filename: []const u8) !void {
    _ = allocator;

    var video_ctx = try VideoContext.init();
    defer video_ctx.deinit();

    // Capture a frame
    var frame: [*c]c.AVFrame = try video_ctx.captureFrame();
    const frame_ptr: [*c][*c]c.AVFrame = &frame;
    defer c.av_frame_free(frame_ptr);

    // Set up PNG encoder
    var output_ctx: ?*c.AVFormatContext = null;
    const alloc_ret = c.avformat_alloc_output_context2(
        &output_ctx,
        null,
        "image2", // Use image2 muxer instead of 'png'
        filename.ptr,
    );
    if (alloc_ret < 0) {
        return error.OutputContextAllocationFailed;
    }
    defer c.avformat_free_context(output_ctx);

    // Create video stream for output
    const codec = c.avcodec_find_encoder(c.AV_CODEC_ID_PNG);
    if (codec == null) {
        return error.CodecNotFound;
    }

    const out_stream = c.avformat_new_stream(output_ctx, codec);
    if (out_stream == null) {
        return error.StreamCreationFailed;
    }

    // Create codec context
    var codec_ctx = c.avcodec_alloc_context3(codec);
    if (codec_ctx == null) {
        return error.CodecContextAllocationFailed;
    }
    defer c.avcodec_free_context(&codec_ctx);

    // Set codec parameters
    const max_width: c_int = 1024;
    const max_height: c_int = 768;

    // Calculate scaled dimensions maintaining aspect ratio
    const ScaledDimensions = struct {
        width: c_int,
        height: c_int,
    };

    const getScaledDimensions = struct {
        fn calc(orig_width: c_int, orig_height: c_int, max_w: c_int, max_h: c_int) ScaledDimensions {
            const w_scale: f32 = @as(f32, @floatFromInt(max_w)) / @as(f32, @floatFromInt(orig_width));
            const h_scale: f32 = @as(f32, @floatFromInt(max_h)) / @as(f32, @floatFromInt(orig_height));
            const scale: f32 = @min(w_scale, h_scale);

            return ScaledDimensions{
                .width = @intFromFloat(@round(@as(f32, @floatFromInt(orig_width)) * scale)),
                .height = @intFromFloat(@round(@as(f32, @floatFromInt(orig_height)) * scale)),
            };
        }
    }.calc;

    // Get scaled dimensions
    const scaled_dim = getScaledDimensions(frame.*.width, frame.*.height, max_width, max_height);

    codec_ctx.*.width = scaled_dim.width;
    codec_ctx.*.height = scaled_dim.height;
    codec_ctx.*.pix_fmt = c.AV_PIX_FMT_RGB24;
    codec_ctx.*.time_base = .{ .num = 1, .den = 25 };
    codec_ctx.*.framerate = .{ .num = 25, .den = 1 };

    // Copy parameters from codec context to stream
    if (c.avcodec_parameters_from_context(out_stream.*.codecpar, codec_ctx) < 0) {
        return error.ParametersCopyFailed;
    }

    // Set stream timebase
    out_stream.*.time_base = codec_ctx.*.time_base;

    // Open codec
    if (c.avcodec_open2(codec_ctx, codec, null) < 0) {
        return error.CodecOpenFailed;
    }

    // Create software scaler context
    const sws_ctx = c.sws_getContext(
        frame.*.width,
        frame.*.height,
        frame.*.format,
        scaled_dim.width,
        scaled_dim.height,
        c.AV_PIX_FMT_RGB24,
        c.SWS_BILINEAR,
        null,
        null,
        null,
    );
    if (sws_ctx == null) {
        return error.ScalerContextCreationFailed;
    }
    defer c.sws_freeContext(sws_ctx);

    // Allocate RGB frame
    var rgb_frame = c.av_frame_alloc();
    if (rgb_frame == null) {
        return error.RGBFrameAllocationFailed;
    }
    defer c.av_frame_free(&rgb_frame);

    rgb_frame.*.format = c.AV_PIX_FMT_RGB24;
    rgb_frame.*.width = scaled_dim.width;
    rgb_frame.*.height = scaled_dim.height;

    // Allocate buffer for RGB frame
    const rgb_buffer_size = c.av_image_get_buffer_size(
        c.AV_PIX_FMT_RGB24,
        scaled_dim.width,
        scaled_dim.height,
        1,
    );
    const rgb_buffer = c.av_malloc(@intCast(rgb_buffer_size));
    defer c.av_free(rgb_buffer);

    // Setup RGB frame buffer
    _ = c.av_image_fill_arrays(
        &rgb_frame.*.data[0],
        &rgb_frame.*.linesize[0],
        @ptrCast(rgb_buffer),
        c.AV_PIX_FMT_RGB24,
        scaled_dim.width,
        scaled_dim.height,
        1,
    );

    // Convert frame to RGB
    _ = c.sws_scale(
        sws_ctx,
        &frame.*.data[0],
        &frame.*.linesize[0],
        0,
        frame.*.height,
        &rgb_frame.*.data[0],
        &rgb_frame.*.linesize[0],
    );

    // Open output file
    if (c.avio_open(&output_ctx.?.pb, filename.ptr, c.AVIO_FLAG_WRITE) < 0) {
        return error.OutputFileOpenFailed;
    }
    defer _ = c.avio_closep(&output_ctx.?.pb);

    // Write header
    if (c.avformat_write_header(output_ctx, null) < 0) {
        return error.HeaderWriteFailed;
    }

    // Encode frame
    var out_packet: c.AVPacket = undefined;
    c.av_init_packet(&out_packet);
    defer c.av_packet_unref(&out_packet);

    if (c.avcodec_send_frame(codec_ctx, rgb_frame) < 0) {
        return error.FrameEncodingFailed;
    }

    while (true) {
        const receive_ret = c.avcodec_receive_packet(codec_ctx, &out_packet);
        if (receive_ret == c.AVERROR(c.EAGAIN) or receive_ret == c.AVERROR_EOF) {
            break;
        }
        if (receive_ret < 0) {
            return error.PacketReceiveFailed;
        }

        // Write packet to file
        if (c.av_interleaved_write_frame(output_ctx, &out_packet) < 0) {
            return error.PacketWriteFailed;
        }
    }

    // Write trailer
    if (c.av_write_trailer(output_ctx) < 0) {
        return error.TrailerWriteFailed;
    }

    std.debug.print("Screenshot saved to {s}\n", .{filename});
}
