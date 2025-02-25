const std = @import("std");
const Waveform = @import("waveform.zig");
const Controller = @import("controller.zig");

const Self = @This();

allocator: std.mem.Allocator,
controller: *Controller.Controller,
table: *Waveform.Table,

pub fn sendInit(self: *Self) !void {
    const waveform = try self.table.lookup(0, @intCast(try self.controller.getTemperature()));

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

        data += (dims.stride - (dims.real_width / dims.packed_pixels) * dims.depth) / @sizeOf(u16);
    }
}

pub const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

fn printWaveform(waveform: *const Waveform.Waveform) void {
    var from: usize = 0;
    while (from < 32) : (from += 1) {
        var to: usize = 0;
        while (to < 32) : (to += 1) {
            std.debug.print("{},{},", .{from, to});
            var i: usize = 0;
            while (i < waveform.items.len) : (i += 1) {
                std.debug.print("{},", .{waveform.items[i][from][to]});
            }
            std.debug.print("\n", .{});
        }
    }
}

pub fn sendRect(self: *Self, rect: Rect) !void {
    const a2 = 6;
    const waveform = try self.table.lookup(a2, @intCast(try self.controller.getTemperature()));

    const dims = self.controller.dims;
    const frame_size = self.controller.blank_frame.len;

    const black_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(black_frame);
    @memcpy(black_frame, self.controller.blank_frame);
    fillRectWithOp(black_frame, &dims, .Black, rect);

    const white_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(white_frame);
    @memcpy(white_frame, self.controller.blank_frame);
    fillRectWithOp(white_frame, &dims, .White, rect);

    for (waveform.items) |matrix| {
        const op = matrix[30][0];

        const frame = switch (op) {
            .Noop => self.controller.blank_frame,
            .Black => black_frame,
            .White => white_frame,
            else => unreachable,
        };

        @memcpy(self.controller.getBackBuffer(), frame);

        try self.controller.pageFlip();
    }
}

fn alignRect(rect: Rect, dims: *const Controller.FramebufferDimensions) Rect {
    const mask = dims.packed_pixels - 1;

    if ((rect.width & mask) == 0 and (rect.x & mask) == 0) {
        return rect;
    }

    var result = rect;

    result.x = rect.x & ~mask;
    const pad_left = rect.x & mask;
    result.width = (pad_left + rect.width + mask) & ~mask;

    return result;
}

fn fillRectWithOp(frame: []u8, dims: *const Controller.FramebufferDimensions, phase: Waveform.Phase, unalignedRect: Rect) void {
    const rect = alignRect(unalignedRect, dims);

    var data: [*]u16 = @alignCast(@ptrCast(
        frame.ptr + (dims.upper_margin + @as(u32, @intCast(rect.y))) * dims.stride + (dims.left_margin + @as(u32, @intCast(rect.x)) / dims.packed_pixels) * dims.depth,
    ));

    var y: usize = 0;
    while (y < rect.height) : (y += 1) {
        var x: usize = 0;
        while (x < rect.width) : (x += dims.packed_pixels) {
            var phases: u16 = 0;

            var j: u32 = 0;
            while (j < dims.packed_pixels) : (j += 1) {
                phases <<= 2;
                phases |= @as(u8, @intFromEnum(phase));
            }

            data[0] = phases;
            data += 2;
        }

        data += (dims.stride - (@as(u32, @intCast(rect.width)) / dims.packed_pixels) * dims.depth) / @sizeOf(u16);
    }
}
