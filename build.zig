const std = @import("std");

// Zig 0.13.0 required.

pub fn build(b: *std.Build) void {
    const version = "0.0.1";

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "piglet",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("httpz", httpz.module("httpz"));

    const websocket = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("websocket", websocket.module("websocket"));

    exe.root_module.addOptions("build_config", build_options);

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigimg", zigimg_dependency.module("zigimg"));

    // Add MinGW include paths - these will bring in all the Windows headers
    // Really only helpful for the Zig language server on macOS
    exe.addSystemIncludePath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/Cellar/mingw-w64/12.0.0_1/toolchain-x86_64/x86_64-w64-mingw32/include" });
    exe.linkLibC();

    // Add FFmpeg include and lib paths
    exe.addSystemIncludePath(b.path("vendor/ffmpeg/include"));
    exe.addLibraryPath(b.path("vendor/ffmpeg/lib"));

    const target_info = target.result;
    if (target_info.os.tag == .windows) {
        // Add MinGW library paths
        exe.addLibraryPath(.{ .cwd_relative = "/usr/local/x86_64-w64-mingw32/lib" });
        exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/Cellar/mingw-w64/12.0.0_2/toolchain-x86_64/x86_64-w64-mingw32/lib" });

        // Windows system libraries - add these before FFmpeg
        exe.linkSystemLibrary("kernel32"); // For windows time functions
        exe.linkSystemLibrary("bcrypt"); // For crypto functions
        exe.linkSystemLibrary("ole32"); // For COM/Media Foundation
        exe.linkSystemLibrary("winmm"); // For additional time functions
        exe.linkSystemLibrary("ntdll"); // For additional system functions

        // Add static winpthreads for POSIX time functions
        exe.addObjectFile(.{ .cwd_relative = "/opt/homebrew/Cellar/mingw-w64/12.0.0_2/toolchain-x86_64/x86_64-w64-mingw32/lib/libwinpthread.a" });

        // Define Windows threading model to match FFmpeg build
        exe.defineCMacro("WIN32_LEAN_AND_MEAN", null);
        exe.defineCMacro("HAVE_WIN32_THREADS", "1");
        exe.defineCMacro("PTWS32_STATIC_LIB", "1");
        exe.defineCMacro("_WIN32_WINNT", "0x0601"); // Windows 7 and above

        // Third-party libraries (from MinGW)
        exe.linkSystemLibrary("z"); // zlib for compression
        exe.addObjectFile(.{ .cwd_relative = "/usr/local/x86_64-w64-mingw32/lib/libx264.a" });
        exe.linkSystemLibrary("d3d11"); // Already present
    }

    // Link FFmpeg static libraries
    exe.linkSystemLibrary("avcodec");
    exe.linkSystemLibrary("avfilter");
    exe.linkSystemLibrary("avformat");
    exe.linkSystemLibrary("avutil");
    exe.linkSystemLibrary("swresample");
    exe.linkSystemLibrary("swscale");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
