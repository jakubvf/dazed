const Self = @This();

display: DisplayInterface,
allocator: std.mem.Allocator,
waveform_table: Waveform.Table,
ft_lib: ft.Library,
ft_face: ft.Face,
current_frame: []u8,
last_flushed_frame: []u8,
dirty_rect: ?Rect,

extern fn drawCharNeon(frame: *c_char, frame_len: c_ulong, bitmap_buffer: *c_char, bitmap_width: c_int, bitmap_height: c_int, x_offset: c_int, y_offset: c_int, phase: c_ushort) callconv(.C) void;

pub fn init(allocator: std.mem.Allocator, display: DisplayInterface, waveform_table: Waveform.Table, ft_lib: ft.Library, ft_face: ft.Face) !Self {
    const current_frame = try allocator.alloc(u8, dims.frame_size);
    @memcpy(current_frame, BlankFrame.get());
    
    const last_flushed_frame = try allocator.alloc(u8, dims.frame_size);
    @memcpy(last_flushed_frame, BlankFrame.get());
    
    return Self{
        .display = display,
        .allocator = allocator,
        .waveform_table = waveform_table,
        .ft_lib = ft_lib,
        .ft_face = ft_face,
        .current_frame = current_frame,
        .last_flushed_frame = last_flushed_frame,
        .dirty_rect = null,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.current_frame);
    self.allocator.free(self.last_flushed_frame);
}

pub fn clear(self: *Self) !void {
    var prof_scope = profiler.profile("DrawingContext.clear");
    defer prof_scope.deinit();

    @memcpy(self.current_frame, BlankFrame.get());
    
    self.dirty_rect = Rect{
        .x = 0,
        .y = 0,
        .width = dims.real_width,
        .height = dims.real_height,
    };
    
    const waveform = try self.waveform_table.lookup(0, @intCast(try self.display.getTemperature()));

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

        @memcpy(self.display.getBackBuffer(), frame);

        try self.display.pageFlip();
    }
    
    // Update last flushed frame after clear
    @memcpy(self.last_flushed_frame, self.current_frame);
    self.dirty_rect = null;
}

pub fn rectangle(self: *Self, rect: Rect) !void {
    var prof_scope = profiler.profile("DrawingContext.rectangle");
    defer prof_scope.deinit();

    fillRectWithOp(self.current_frame, .Black, rect);
    self.expandDirtyRect(rect);
}

pub fn text(self: *Self, x: u32, y: u32, string: []const u8) !void {
    var prof_scope = profiler.profile("DrawingContext.text");
    defer prof_scope.deinit();

    const text_rect = try calculateTextBounds(self.ft_face, x, y, string);
    try fillFrameWithText(self.current_frame, .Black, self.ft_face, x, y, string);
    self.expandDirtyRect(text_rect);
}

const DisplayInterface = @import("Interface.zig");
const std = @import("std");
const Waveform = @import("waveform.zig");
const ft = @import("freetype");
const Rect = @import("rect.zig");
const Phase = Waveform.Phase;
const FramebufferDimensions = @import("framebuffer_dimensions.zig");
const dims = FramebufferDimensions.rm2();
const BlankFrame = @import("blank_frame.zig");
const profiler = @import("../profiler.zig");

// Helper functions copied from display.zig
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

fn fillFrameWithText(frame: []u8, phase: Waveform.Phase, face: ft.Face, x_pos: u32, y_pos: u32, contents: []const u8) !void {
    var prof_scope = profiler.profile("fillFrameWithText");
    defer prof_scope.deinit();

    var x = x_pos;
    var y = y_pos;

    for (contents) |char| {
        const idx = idx: {
            break :idx face.getCharIndex(char) orelse continue;
        };
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

fn expandDirtyRect(self: *Self, rect: Rect) void {
    if (self.dirty_rect) |current| {
        const min_x = @min(current.x, rect.x);
        const min_y = @min(current.y, rect.y);
        const max_x = @max(current.x + current.width, rect.x + rect.width);
        const max_y = @max(current.y + current.height, rect.y + rect.height);
        
        self.dirty_rect = Rect{
            .x = min_x,
            .y = min_y,
            .width = max_x - min_x,
            .height = max_y - min_y,
        };
    } else {
        self.dirty_rect = rect;
    }
}

pub fn flush(self: *Self) !void {
    if (self.dirty_rect == null) return;
    
    var prof_scope = profiler.profile("DrawingContext.flush");
    defer prof_scope.deinit();
    
    const a2 = 6;
    const waveform = try self.waveform_table.lookup(a2, @intCast(try self.display.getTemperature()));
    
    // Create frames with only the differences since last flush
    const black_frame = try self.allocator.alloc(u8, dims.frame_size);
    defer self.allocator.free(black_frame);
    @memcpy(black_frame, BlankFrame.get());
    createDifferenceFrame(black_frame, self.current_frame, self.last_flushed_frame, .Black);
    
    const white_frame = try self.allocator.alloc(u8, dims.frame_size);
    defer self.allocator.free(white_frame);
    @memcpy(white_frame, BlankFrame.get());
    
    for (waveform.items) |matrix| {
        const op = matrix[30][0];
        
        const frame = switch (op) {
            .Noop => BlankFrame.get(),
            .Black => black_frame,
            .White => white_frame,
            else => unreachable,
        };
        
        @memcpy(self.display.getBackBuffer(), frame);
        try self.display.pageFlip();
    }
    
    // Update last flushed frame
    @memcpy(self.last_flushed_frame, self.current_frame);
    self.dirty_rect = null;
}

fn createDifferenceFrame(dest_frame: []u8, current_frame: []const u8, last_frame: []const u8, phase: Phase) void {
    const phase_bits: u16 = @intFromEnum(phase);
    
    // Process the frame word by word (each word contains multiple pixels)
    var data_offset: usize = dims.upper_margin * dims.stride + dims.left_margin * dims.depth;
    
    var y: usize = 0;
    while (y < dims.real_height) : (y += 1) {
        var x: usize = 0;
        while (x < dims.real_width) : (x += dims.packed_pixels) {
            const word_offset = data_offset + (x / dims.packed_pixels) * dims.depth;
            
            const current_word: *const u16 = @alignCast(@ptrCast(&current_frame[word_offset]));
            const last_word: *const u16 = @alignCast(@ptrCast(&last_frame[word_offset]));
            const dest_word: *u16 = @alignCast(@ptrCast(&dest_frame[word_offset]));
            
            // Only update pixels that have changed
            if (current_word.* != last_word.*) {
                // Check each pixel in the word
                var pixel_phases: u16 = 0;
                
                var pixel_idx: u32 = 0;
                while (pixel_idx < dims.packed_pixels) : (pixel_idx += 1) {
                    const shift_amount: u4 = @intCast((dims.packed_pixels - 1 - pixel_idx) * 2);
                    const pixel_mask: u16 = @as(u16, 0b11) << shift_amount;
                    
                    const current_pixel = (current_word.* & pixel_mask) >> shift_amount;
                    const last_pixel = (last_word.* & pixel_mask) >> shift_amount;
                    
                    pixel_phases <<= 2;
                    if (current_pixel != last_pixel) {
                        // Pixel changed, apply the phase
                        pixel_phases |= phase_bits;
                    } else {
                        // Pixel unchanged, use Noop
                        pixel_phases |= @intFromEnum(Phase.Noop);
                    }
                }
                
                dest_word.* = pixel_phases;
            }
        }
        
        data_offset += dims.stride;
    }
}

fn calculateTextBounds(face: ft.Face, x_pos: u32, y_pos: u32, contents: []const u8) !Rect {
    var min_x: i32 = @intCast(x_pos);
    var max_x: i32 = @intCast(x_pos);
    var min_y: i32 = @intCast(y_pos);
    var max_y: i32 = @intCast(y_pos);
    
    var x: i32 = @intCast(x_pos);
    var y: i32 = @intCast(y_pos);
    
    for (contents) |char| {
        const idx = face.getCharIndex(char) orelse continue;
        try face.loadGlyph(idx, .{ .no_hinting = true });
        
        const metrics = &face.handle.*.glyph.*.metrics;
        const glyph_width: i32 = @intCast(metrics.horiAdvance >> 6);
        const glyph_height: i32 = @intCast(metrics.height >> 6);
        
        const x_bearing: i32 = @intCast(metrics.horiBearingX >> 6);
        const y_bearing: i32 = @intCast(metrics.horiBearingY >> 6);
        
        const char_left = x + x_bearing;
        const char_right = char_left + glyph_width;
        const char_top = y - y_bearing;
        const char_bottom = char_top + glyph_height;
        
        min_x = @min(min_x, char_left);
        max_x = @max(max_x, char_right);
        min_y = @min(min_y, char_top);
        max_y = @max(max_y, char_bottom);
        
        x += glyph_width;
        if (x >= dims.real_width) {
            x = dims.left_margin;
            y += glyph_height;
        }
    }
    
    return Rect{
        .x = @max(0, min_x),
        .y = @max(0, min_y),
        .width = @max(0, max_x - min_x),
        .height = @max(0, max_y - min_y),
    };
}

fn drawChar(frame: []u8, bitmap: *ft.c.FT_Bitmap, x_offset: i32, y_offset: i32, phase: Phase) void {
    const width: i32 = @intCast(bitmap.width);
    const height: i32 = @intCast(bitmap.rows);
    const bitmap_buffer = @as([*]u8, @ptrCast(bitmap.buffer));
    const phase_bits: u16 = @intFromEnum(phase);

    var y: i32 = 0;
    while (y < height) : (y += 1) {
        const buffer_y_pos = y + y_offset;
        if (buffer_y_pos < 0 or buffer_y_pos >= @as(i32, @intCast(dims.real_height))) continue;
        const buffer_y = dims.real_height - @as(u32, @intCast(buffer_y_pos)) - 1;

        var x: i32 = 0;
        while (x < width) {
            const buffer_x = x + x_offset;
            if (buffer_x < dims.left_margin or buffer_x >= dims.real_width) {
                x += 1;
                continue;
            }

            // Process pixels up to the next word boundary
            const pixels_remaining_in_word = dims.packed_pixels - (@as(u32, @intCast(buffer_x)) % dims.packed_pixels);
            const pixels_to_process = @min(pixels_remaining_in_word, @as(u32, @intCast(width - x)));
            
            // Calculate word position using the actual buffer_x
            const byte_pos = (dims.upper_margin + buffer_y) * dims.stride + 
                           (dims.left_margin + @as(u32, @intCast(buffer_x)) / dims.packed_pixels) * dims.depth;
            const pixel_word: *u16 = @alignCast(@ptrCast(&frame[byte_pos]));
            
            var word_value = pixel_word.*;
            var changed = false;
            
            // Process pixels in this word
            var px: u32 = 0;
            while (px < pixels_to_process) : (px += 1) {
                const bitmap_index: usize = @intCast(y * width + x + @as(i32, @intCast(px)));
                const pixel_value: u8 = bitmap_buffer[bitmap_index];
                
                if (pixel_value != 0) {
                    const pixel_pos = (@as(u32, @intCast(buffer_x)) + px) % dims.packed_pixels;
                    const shift_amount: u4 = @intCast((dims.packed_pixels - 1 - pixel_pos) * 2);
                    const pixel_mask = ~(@as(u16, 0b11) << shift_amount);
                    
                    word_value = (word_value & pixel_mask) | (phase_bits << shift_amount);
                    changed = true;
                }
            }
            
            if (changed) {
                pixel_word.* = word_value;
            }
            
            x += @intCast(pixels_to_process);
        }
    }
}
