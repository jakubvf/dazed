const std = @import("std");
const Controller = @import("controller.zig");
const Waveformer = @import("waveforms/waveformer2.zig");
const Generator = @import("generator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer gpa.deinit();
    const allocator = gpa.allocator();

    var controller = try Controller.Controller.init();
    try controller.start(allocator);
    defer controller.stop();

    const table = try Waveformer.giveMeWaveform(allocator);
    defer Waveformer.destroyWaveform(allocator, table);

    var generator = try Generator.init(allocator, &controller, table);
    defer generator.deinit();
    try generator.update_display(&[_]u8 {30} ** (1404 * 1872), Generator.UpdateRegion{
        .top = 0,
        .left = 0,
        .width = 1404,
        .height = 1872,
    });
}
