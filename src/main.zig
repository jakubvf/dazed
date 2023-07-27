const std = @import("std");
const Waveform = @import("waveform.zig");

pub fn main() !void {
    std.debug.print("Starting up\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    _ = try Waveform.discover_wbf_file(allocator);
    std.debug.print("Going down\n", .{});
}
