const std = @import("std");
const Controller = @import("controller.zig");
const Display = @import("display.zig");
const Waveform = @import("waveform.zig");
const ft = @import("freetype");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // TODO: Enable this once I fix all memory leaks :D
    // defer gpa.deinit();
    const allocator = gpa.allocator();

    var controller = try Controller.Controller.init();
    try controller.start(allocator);
    defer controller.stop();

    var table = try Waveform.Table.from_wbf(allocator, "/usr/share/remarkable/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf");

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

    // Touchscreen input
    {
        const LinuxInput = (@cImport(@cInclude("linux/input.h")));
        const InputEvent = LinuxInput.input_event;

        const touch_input_file = try std.fs.openFileAbsolute("/dev/input/event2", .{});
        defer touch_input_file.close();

        var event: InputEvent = undefined;
        while (true) {
            const bytes_read = try touch_input_file.read(std.mem.asBytes(&event));
            if (bytes_read == 0) {
                std.log.err("bytes_read = 0, quitting", .{});
                return;
            }

            if (bytes_read != @sizeOf(InputEvent)) {
                std.log.err("Short read {}b, expected {}b", .{ bytes_read, @sizeOf((InputEvent)) });
                break;
            }

            if (event.type == LinuxInput.EV_ABS) {
                switch (event.code) {
                    LinuxInput.ABS_MT_POSITION_X => std.debug.print("X: {}\n", .{event.value}),
                    LinuxInput.ABS_MT_POSITION_Y => std.debug.print("Y: {}\n", .{event.value}),
                    LinuxInput.ABS_MT_SLOT => std.debug.print("Slot: {}\n", .{event.value}),
                    LinuxInput.ABS_MT_TRACKING_ID => std.debug.print("Tracking ID: {}\n", .{event.value}),
                    LinuxInput.ABS_MT_PRESSURE => std.debug.print("Pressure: {}\n", .{event.value}),
                    else => {},
                }
            } else if (event.type == LinuxInput.EV_SYN) {
                std.debug.print("==== FRAME SYNC ====\n", .{});
            }
        }
    }
}
