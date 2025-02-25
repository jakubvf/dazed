const std = @import("std");
const Controller = @import("controller.zig");
const Display = @import("display.zig");
const Waveform = @import("waveform.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer gpa.deinit();
    const allocator = gpa.allocator();

    var controller = try Controller.Controller.init();
    try controller.start(allocator);
    defer controller.stop();

    var table = try Waveform.Table.from_wbf(allocator, "/usr/share/remarkable/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf");

    var display = Display{
        .allocator = allocator,
        .controller = &controller,
        .table = &table,
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


}
