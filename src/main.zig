const std = @import("std");
const Display = @import("display.zig");
const BuildConfig = @import("build_config");
const HackerNews = @import("hackernews.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var display = try Display.init(allocator, if (BuildConfig.emulator) .sdl3 else .rm2);
    defer display.deinit();
    try display.clear();

    return HackerNews.run(allocator, &display);
}
