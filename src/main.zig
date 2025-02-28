const std = @import("std");
const BlankFrame = @import("display/blank_frame.zig");
const Controller = @import("display/sdl3.zig");
const Display = @import("display/display.zig");
const Waveform = @import("display/waveform.zig");
const ft = @import("freetype");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // TODO: Enable this once I fix all memory leaks :D
    // defer gpa.deinit();
    const allocator = gpa.allocator();

    BlankFrame.init(allocator);

    var controller = try Controller.init(allocator);
    defer controller.deinit();

    // var table = try Waveform.Table.from_wbf(allocator, "/usr/share/remarkable/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf");
    var table = try Waveform.Table.from_wbf(allocator, "src/waveforms/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf");

    const ft_lib = try ft.Library.init();
    defer ft_lib.deinit();

    const face = try ft_lib.initMemoryFace(@embedFile("fonts/Roboto_Mono/static/RobotoMono-Bold.ttf"), 0);
    defer face.deinit();
    const em_size = 48 * 64;
    try face.setPixelSizes(0, em_size >> 6);
    try face.selectCharmap(.unicode);

    var display = Display{
        .allocator = allocator,
        .controller = &controller,
        .table = &table,
        .ft_face = face,
    };
    try display.sendInit();

    try display.sendRect(.{
        .x = 100,
        .y = 500,
        .width = 500,
        .height = 200,
    });

    try display.sendRect(.{
        .x = 100,
        .y = 100,
        .width = 400,
        .height = 100,
    });

    try display.sendRect(.{
        .x = 1000,
        .y = 1000,
        .width = 100,
        .height = 100,
    });

    try display.sendPixel(998, 1000);
    try display.sendPixel(997, 1000);
    try display.sendPixel(996, 1000);

    try display.sendText(600, 600, "Helloworld!");

    controller.waitForExit();
}
