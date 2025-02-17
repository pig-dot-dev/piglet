// Configuration for video streaming

/// Target frames per second
fps: f64 = 30.0,

/// Target bitrate in bits per second
bitrate: u32 = 2_500_000,

/// H.264 encoding preset (affects CPU usage vs quality)
/// Options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
preset: []const u8 = "ultrafast", // Match FFmpeg command

/// H.264 tune parameter
/// Options: film, animation, grain, stillimage, fastdecode, zerolatency
tune: []const u8 = "zerolatency",

/// H.264 profile
/// Options: baseline, main, high
profile: []const u8 = "baseline",

/// Group of Pictures (GOP) size - interval between keyframes
gop_size: u32 = 30,

/// Maximum number of B-frames between reference frames
max_b_frames: u32 = 0,
