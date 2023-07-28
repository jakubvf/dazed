const std = @import("std");
const Waveform = @import("waveform.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    std.debug.print("Found WBF file: {s}\n", .{
        (try Waveform.discover_wbf_file(allocator)).?,
    });
}
