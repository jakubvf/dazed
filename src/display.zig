const std = @import("std");
const Waveform = @import("waveform.zig");
const Controller = @import("controller.zig");

const Self = @This();

allocator: std.mem.Allocator,
controller: *Controller.Controller,
table: *Waveform.Table,

pub fn sendInit(self: *Self) !void {
    std.log.debug("Generating init transition", .{});

    // Mode 0 (INIT) is used for display initialization
    // Temperature value is less critical for init, but we'll use 20°C as a standard value
    _ = try self.controller.getTemperature();
    const waveform = try self.table.lookup(0, 20);

    const dims = self.controller.dims;
    const frame_size = self.controller.blank_frame.len;

    const white_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(white_frame);
    @memcpy(white_frame, self.controller.blank_frame);
    fillFrameWithOp(white_frame, &dims, .White);

    const black_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(black_frame);
    @memcpy(black_frame, self.controller.blank_frame);
    fillFrameWithOp(black_frame, &dims, .Black);

    for (waveform.items) |matrix| {
        const op = matrix[0][0];

        const frame = switch (op) {
            .Noop => self.controller.blank_frame,
            .White => white_frame,
            .Black => black_frame,
            else => unreachable,
        };

        @memcpy(self.controller.getBackBuffer(), frame);

        try self.controller.pageFlip();
    }
}

fn fillFrameWithOp(frame: []u8, dims: *const Controller.FramebufferDimensions, phase: Waveform.Phase) void {
    var data: [*]u16 = @alignCast(@ptrCast(frame.ptr + dims.upper_margin * dims.stride + dims.left_margin * dims.depth));

    var y: usize = 0;
    while (y < dims.real_height) : (y += 1) {
        var x: usize = 0;
        while (x < dims.real_width) : (x += dims.packed_pixels) {
            var phases: u16 = 0;

            var j: u32 = 0;
            while (j < dims.packed_pixels) : (j += 1) {
                phases <<= 2;
                phases |= @as(u8, @intFromEnum(phase));
            }

            data[0] = phases;
            data += 2;
        }

        data += (
            dims.stride - (dims.real_width / dims.packed_pixels) * dims.depth
        ) / @sizeOf(u16);
    }
}
