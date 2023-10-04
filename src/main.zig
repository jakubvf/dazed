const std = @import("std");
const Waveform = @import("waveform.zig");
const Controller = @import("controller.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const wbf_path = (try Waveform.discover_wbf_file(allocator)).?;
    std.debug.print("Found WBF file: {s}\n", .{wbf_path});
    const table = Waveform.Table.from_wbf(allocator, wbf_path);
    std.debug.print("Table: {any}\n", .{table});
    const controller = Controller.open_remarkable2();
    _ = controller;
}
