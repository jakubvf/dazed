const std = @import("std");
const ft = @import("freetype");
const Rect = @import("display/rect.zig");
const Waveform = @import("display/waveform.zig");
const Phase = Waveform.Phase;

const FramebufferDimensions = @import("display/framebuffer_dimensions.zig");
const dims = FramebufferDimensions.rm2();

const BlankFrame = @import("display/blank_frame.zig");

pub const DisplayBackend = enum {
    rm2,
    sdl3,
};

pub fn init(allocator: std.mem.Allocator, comptime backend: DisplayBackend) !Display(backend) {
    return try Display(backend).init(allocator);
}

pub fn Display(comptime backend: DisplayBackend) type {
    const Controller = switch (backend) {
        .sdl3 => @import("display/sdl3.zig"),
        .rm2 => @import("display/rm2.zig"),
    };
    const wbf_file = switch (backend) {
        .rm2 => "/usr/share/remarkable/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf",
        .sdl3 => "src/waveforms/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf",
    };

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        controller: Controller,
        table: Waveform.Table,
        ft_lib: ft.Library,
        ft_face: ft.Face,

        pub fn init(allocator: std.mem.Allocator) !Self {
            BlankFrame.init(allocator);

            var self: Self = undefined;

            self.allocator = allocator;
            self.controller = try Controller.init(allocator);
            self.table = try Waveform.Table.fromWbf(allocator, wbf_file);
            self.ft_lib = try ft.Library.init();
            self.ft_face = ff: {
                const face = try self.ft_lib.initMemoryFace(@embedFile("fonts/Roboto_Mono/static/RobotoMono-Bold.ttf"), 0);
                try face.selectCharmap(.unicode);

                break :ff face;
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            // Waiting for exit here is sussy!
            // TODO: Figure out a better place to place this.
            self.controller.waitForExit();

            BlankFrame.deinit(self.allocator);

            self.controller.deinit();
            self.table.deinit(self.allocator);
            self.ft_face.deinit();
            self.ft_lib.deinit();
        }

        pub fn clear(self: *Self) !void {
            const waveform = try self.table.lookup(0, @intCast(try self.controller.getTemperature()));

            const white_frame = try self.allocator.alloc(u8, dims.frame_size);
            defer self.allocator.free(white_frame);
            @memcpy(white_frame, BlankFrame.get());
            fillFrameWithOp(white_frame, .White);

            const black_frame = try self.allocator.alloc(u8, dims.frame_size);
            defer self.allocator.free(black_frame);
            @memcpy(black_frame, BlankFrame.get());
            fillFrameWithOp(black_frame, .Black);

            for (waveform.items) |matrix| {
                const op = matrix[0][0];

                const frame = switch (op) {
                    .Noop => BlankFrame.get(),
                    .White => white_frame,
                    .Black => black_frame,
                    else => unreachable,
                };

                @memcpy(self.controller.getBackBuffer(), frame);

                try self.controller.pageFlip();
            }
        }

        pub fn rectangle(self: *Self, rect: Rect) !void {
            const a2 = 6;
            const waveform = try self.table.lookup(a2, @intCast(try self.controller.getTemperature()));

            const frame_size = dims.frame_size;

            const black_frame = try self.allocator.alloc(u8, frame_size);
            defer self.allocator.free(black_frame);
            @memcpy(black_frame, BlankFrame.get());
            fillRectWithOp(black_frame, .Black, rect);

            const white_frame = try self.allocator.alloc(u8, frame_size);
            defer self.allocator.free(white_frame);
            @memcpy(white_frame, BlankFrame.get());
            fillRectWithOp(white_frame, .White, rect);

            for (waveform.items) |matrix| {
                const op = matrix[30][0];

                const frame = switch (op) {
                    .Noop => BlankFrame.get(),
                    .Black => black_frame,
                    .White => white_frame,
                    else => unreachable,
                };

                @memcpy(self.controller.getBackBuffer(), frame);

                try self.controller.pageFlip();
            }
        }

        /// Great for debugging, but don't use this too often.
        /// It's super ineffcient to compute one pixel at a time. Rather, try to handle groups of pixels.
        pub fn pixel(self: *Self, x: u32, y: u32) !void {
            const a2 = 6;
            const waveform = try self.table.lookup(a2, @intCast(try self.controller.getTemperature()));

            const frame_size = dims.frame_size;
            const black_frame = try self.allocator.alloc(u8, frame_size);
            defer self.allocator.free(black_frame);
            @memcpy(black_frame, BlankFrame.get());

            setPixel(black_frame, .Black, x, y);

            for (waveform.items) |matrix| {
                const op = matrix[30][0];

                const frame = switch (op) {
                    .Noop => BlankFrame.get(),
                    .Black => black_frame,
                    else => unreachable,
                };

                @memcpy(self.controller.getBackBuffer(), frame);

                try self.controller.pageFlip();
            }
        }

        pub fn text(self: *Self, x: u32, y: u32, string: []const u8) !void {
            const a2 = 6;
            const waveform = try self.table.lookup(a2, @intCast(try self.controller.getTemperature()));

            const frame_size = dims.frame_size;

            const black_frame = try self.allocator.alloc(u8, frame_size);
            defer self.allocator.free(black_frame);
            @memcpy(black_frame, BlankFrame.get());
            try fillFrameWithText(black_frame, .Black, self.ft_face, x, y, string);

            const white_frame = try self.allocator.alloc(u8, frame_size);
            defer self.allocator.free(white_frame);
            @memcpy(white_frame, BlankFrame.get());
            try fillFrameWithText(white_frame, .White, self.ft_face, x, y, string);

            for (waveform.items) |matrix| {
                const op = matrix[30][0];

                const frame = switch (op) {
                    .Noop => BlankFrame.get(),
                    .Black => black_frame,
                    .White => white_frame,
                    else => unreachable,
                };

                @memcpy(self.controller.getBackBuffer(), frame);

                try self.controller.pageFlip();
            }
        }
    };
}

//
//
// Helper functions bellow
//
//

fn fillFrameWithOp(frame: []u8, phase: Phase) void {
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

// This may be unused but it came in useful once so I'm keeping it
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

fn alignRect(rect: Rect) Rect {
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

fn fillRectWithOp(frame: []u8, phase: Phase, unalignedRect: Rect) void {
    const rect = alignRect(unalignedRect);

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

fn setPixel(frame: []u8, phase: Phase, x: u32, y: u32) void {
    const byte_pos = (dims.upper_margin + @as(u32, @intCast(y))) * dims.stride +
        (dims.left_margin + @as(u32, @intCast(x)) / dims.packed_pixels) * dims.depth;

    const pixel_word: *u16 = @alignCast(@ptrCast(&frame[byte_pos]));

    const pixel_pos_in_word = x % dims.packed_pixels;
    const shift_amount: u4 = @intCast((dims.packed_pixels - 1 - pixel_pos_in_word) * 2);

    const pixel_mask = ~(@as(u16, 0b11) << shift_amount);

    pixel_word.* = (pixel_word.* & pixel_mask) | (@as(u16, @intFromEnum(phase)) << shift_amount);
}

fn fillFrameWithText(frame: []u8, phase: Waveform.Phase, face: ft.Face, x_pos: u32, y_pos: u32, text: []const u8) !void {
    var x = x_pos;
    var y = y_pos;

    for (text) |char| {
        const idx = face.getCharIndex(char).?;
        try face.loadGlyph(idx, .{ .no_hinting = true });
        try face.renderGlyph(.normal);

        const bitmap = &face.handle.*.glyph.*.bitmap;
        const metrics = &face.handle.*.glyph.*.metrics;
        const glyph_height: u32 = @intCast(bitmap.rows);

        if (bitmap.buffer != null) {
            const x_offset: i32 = @divFloor(@as(i32, @intCast(metrics.horiBearingX)), 64);
            const y_offset: i32 = @divFloor(@as(i32, @intCast(metrics.horiBearingY)), 64);

            const draw_x: i32 = @as(i32, @intCast(x)) + x_offset;
            const draw_y: i32 = @as(i32, @intCast(dims.real_height)) - @as(i32, @intCast(y)) - y_offset;
            drawChar(frame, bitmap, draw_x, draw_y, phase);
        }
        x += @intCast(metrics.horiAdvance >> 6);
        if (x >= dims.real_width) {
            x = dims.left_margin;
            y += glyph_height;
        }
    }
}

fn drawChar(frame: []u8, bitmap: *ft.c.FT_Bitmap, x_offset: i32, y_offset: i32, phase: Phase) void {
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
                    // Calling setPixel for every pixel of the glyph bitmap is wasteful.
                    // I think handling mutliple pixels at once should possible.
                    setPixel(frame, phase, @intCast(buffer_x), @intCast(buffer_y));
                }
            }
        }
    }
}

fn drawHorizontalLine(frame: []u8, y: u32, width: u32, phase: Phase) void {
    if (y < 0 or y >= @divFloor(@as(u32, @intCast(frame.len)), width)) return;

    var x: u32 = 0;
    while (x < width) : (x += 1) {
        setPixel(frame, phase, x, y);
    }
}
