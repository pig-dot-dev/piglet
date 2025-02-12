const std = @import("std");
const build_config = @import("build_config");
const os = std.os;
const fs = std.fs;
const win = std.os.windows;

const CONFIG_DIR = ".piglet";
const CONFIG_FILE = "config.json";

const Config = struct {
    version: []const u8,
    fingerprint: []const u8,

    pub fn init(allocator: std.mem.Allocator, version: []const u8, fingerprint: []const u8) !Config {
        return Config{
            .version = try allocator.dupe(u8, version),
            .fingerprint = try allocator.dupe(u8, fingerprint),
        };
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.fingerprint);
    }
};

fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    var envMap = try std.process.getEnvMap(allocator);
    defer envMap.deinit();

    const home = envMap.get("LOCALAPPDATA") orelse return error.NoHomeDir;
    return std.fs.path.join(allocator, &.{ home, CONFIG_DIR });
}

pub fn getConfig(allocator: std.mem.Allocator) !Config {
    const config_dir = try getConfigDir(allocator);
    const config_path = try std.fs.path.join(allocator, &.{ config_dir, CONFIG_FILE });

    // read
    var config_file = fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // generate config if first use
            const config = try writeNewConfig(allocator, config_dir, config_path);
            return config;
        },
        else => return err,
    };
    defer config_file.close();

    const contents = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    const config = try std.json.parseFromSlice(Config, allocator, contents, .{});
    defer config.deinit();

    return Config.init(allocator, config.value.version, config.value.fingerprint);
}

fn writeNewConfig(allocator: std.mem.Allocator, config_dir: []const u8, config_path: []const u8) !Config {
    // Ensure config directory exists
    try fs.makeDirAbsolute(config_dir);

    var config_file = try fs.createFileAbsolute(config_path, .{});
    defer config_file.close();

    const fingerprint = try generateUUID();

    const config = try Config.init(allocator, build_config.version, &fingerprint);

    const contents = try std.json.stringifyAlloc(allocator, config, .{});
    defer allocator.free(contents);

    try config_file.writeAll(contents);

    return config;
}

pub fn generateUUID() ![36]u8 {
    var rnd = std.crypto.random;
    var uuid: [16]u8 = undefined;
    rnd.bytes(&uuid);

    // Set version to 4 (random)
    uuid[6] = (uuid[6] & 0x0f) | 0x40;
    // Set variant to RFC4122
    uuid[8] = (uuid[8] & 0x3f) | 0x80;

    // Format UUID string
    var result: [36]u8 = undefined;
    _ = try std.fmt.bufPrint(
        &result,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            uuid[0],  uuid[1],  uuid[2],  uuid[3],
            uuid[4],  uuid[5],  uuid[6],  uuid[7],
            uuid[8],  uuid[9],  uuid[10], uuid[11],
            uuid[12], uuid[13], uuid[14], uuid[15],
        },
    );

    return result;
}
