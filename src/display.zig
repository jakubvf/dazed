const std = @import("std");
const Waveform = @import("waveform.zig");
const Controller = @import("controller.zig");
const ft = @import("freetype");

const Self = @This();

allocator: std.mem.Allocator,
controller: *Controller.Controller,
table: *Waveform.Table,
ft_face: ft.Face,

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
            std.debug.print("{},{},", .{ from, to });
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

pub fn sendPixel(self: *Self, x: usize, y: usize) !void {
    const a2 = 6;
    const waveform = try self.table.lookup(a2, @intCast(try self.controller.getTemperature()));

    const frame_size = self.controller.blank_frame.len;
    const black_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(black_frame);
    @memcpy(black_frame, self.controller.blank_frame);

    setPixel(black_frame, &self.controller.dims, .Black, x, y);

    for (waveform.items) |matrix| {
        const op = matrix[30][0];

        const frame = switch (op) {
            .Noop => self.controller.blank_frame,
            .Black => black_frame,
            else => unreachable,
        };

        @memcpy(self.controller.getBackBuffer(), frame);

        try self.controller.pageFlip();
    }
}

fn setPixel(frame: []u8, dims: *const Controller.FramebufferDimensions, phase: Waveform.Phase, x: u32, y: u32) void {
    const byte_pos = (dims.upper_margin + @as(u32, @intCast(y))) * dims.stride +
        (dims.left_margin + @as(u32, @intCast(x)) / dims.packed_pixels) * dims.depth;

    const pixel_word: *u16 = @alignCast(@ptrCast(&frame[byte_pos]));

    const pixel_pos_in_word = x % dims.packed_pixels;
    const shift_amount: u4 = @intCast((dims.packed_pixels - 1 - pixel_pos_in_word) * 2);

    const pixel_mask = ~(@as(u16, 0b11) << shift_amount);

    pixel_word.* = (pixel_word.* & pixel_mask) | (@as(u16, @intFromEnum(phase)) << shift_amount);
}

pub fn sendText(self: *Self, x: u32, y: u32, text: []const u8) !void {
    const a2 = 6;
    const waveform = try self.table.lookup(a2, @intCast(try self.controller.getTemperature()));

    const dims = self.controller.dims;
    const frame_size = self.controller.blank_frame.len;

    const black_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(black_frame);
    @memcpy(black_frame, self.controller.blank_frame);
    try fillFrameWithText(black_frame, &dims, .Black, self.ft_face, x, y, text);

    const white_frame = try self.allocator.alloc(u8, frame_size);
    defer self.allocator.free(white_frame);
    @memcpy(white_frame, self.controller.blank_frame);
    try fillFrameWithText(white_frame, &dims, .White, self.ft_face, x, y, text);

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

fn fillFrameWithText(frame: []u8, dims: *const Controller.FramebufferDimensions, phase: Waveform.Phase, face: ft.Face, x_pos: u32, y_pos: u32, text: []const u8) !void {
    _ = phase; //TODO

    var x = x_pos;
    var y = y_pos;

    for (text) |char| {
        const idx = face.getCharIndex(char).?;
        try face.loadGlyph(idx, .{ .no_hinting = true });
        try face.renderGlyph(.normal);

        const bitmap = &face.handle.*.glyph.*.bitmap;
        const metrics = &face.handle.*.glyph.*.metrics;
        const glyph_height: u32 = @intCast(bitmap.rows);

        const x_offset: i32 = @divFloor(@as(i32, @intCast(metrics.horiBearingX)), 64);
        const y_offset: i32 = @divFloor(@as(i32, @intCast(metrics.horiBearingY)), 64);

        const draw_x: i32 = @as(i32, @intCast(x)) + x_offset;
        const draw_y: i32 = @as(i32, @intCast(dims.real_height)) - @as(i32, @intCast(y)) - y_offset;
        drawChar(frame, dims, bitmap, draw_x, draw_y);

        x += @intCast(metrics.horiAdvance >> 6);
        if (x >= dims.real_width) {
            x = dims.left_margin;
            y += glyph_height;
        }
    }

    drawBaseline(frame, dims, y_pos, dims.real_width);
}

fn drawChar(frame: []u8, dims: *const Controller.FramebufferDimensions, bitmap: *ft.c.FT_Bitmap, x_offset: i32, y_offset: i32) void {
    const width: i32 = @intCast(bitmap.width);
    const height: i32 = @intCast(bitmap.rows);
    const bitmap_buffer = @as([*]u8, @ptrCast(bitmap.buffer));

    var y: i32 = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            const buffer_x = x + x_offset;
            const buffer_y = dims.real_height - @as(u32, @intCast((y + y_offset))) - 1;

            if (buffer_x >= dims.left_margin and buffer_x < dims.real_width and buffer_y >= dims.upper_margin and buffer_y < dims.real_height) {
                const bitmap_index: usize = @intCast(y * width + x);

                const pixel_value: u8 = bitmap_buffer[bitmap_index];
                if (pixel_value != 0) {
                    setPixel(frame, dims, .Black, @intCast(buffer_x), @intCast(buffer_y));
                }
            }
        }
    }
}

fn drawBaseline(frame: []u8, dims: *const Controller.FramebufferDimensions, y: u32, width: u32) void {
    if (y < 0 or y >= @divFloor(@as(u32, @intCast(frame.len)), width)) return;

    var x: u32 = 0;
    while (x < width) : (x += 1) {
        setPixel(frame, dims, .Black, x, y);
    }
}
