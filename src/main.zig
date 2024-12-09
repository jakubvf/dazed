const std = @import("std");
const Controller = @import("controller.zig");
const Waveformer = @import("waveforms/waveformer2.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer gpa.deinit();
    const allocator = gpa.allocator();

    var controller = try Controller.Controller.init();
    try controller.start(allocator);
    defer controller.stop();

    const table = try Waveformer.giveMeWaveform(allocator);
    defer Waveformer.destroyWaveform(allocator, table);
}
