const std = @import("std");
const Display = @import("display.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // TODO: Enable this once I fix all memory leaks :D
    // defer gpa.deinit();
    const allocator = gpa.allocator();

    var display = try Display.init(allocator, .sdl3);
    defer display.deinit();
    try display.clear();

    try display.rectangle(.{
        .x = 100,
        .y = 500,
        .width = 500,
        .height = 200,
    });

    try display.rectangle(.{
        .x = 100,
        .y = 100,
        .width = 400,
        .height = 100,
    });

    try display.rectangle(.{
        .x = 1000,
        .y = 1000,
        .width = 100,
        .height = 100,
    });

    try display.pixel(998, 1000);
    try display.pixel(997, 1000);
    try display.pixel(996, 1000);

    try display.text(600, 600, "helloworld!");
}
