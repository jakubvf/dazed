const std = @import("std");
const c = @cImport(@cInclude(("SDL3/SDL.h")));
const ft = @import("freetype");
const Waveform = @import("waveform.zig");
const BlankFrame = @import("blank_frame.zig");

const Self = @This();
const FramebufferDimensions = @import("framebuffer_dimensions.zig");

const dims = FramebufferDimensions.rm2();

allocator: std.mem.Allocator,
window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,
pixels: []u32,
buffers: [dims.frame_count][]u8,
back_buffer_index: u8 = 0,
front_buffer_index: u8 = 0,

fn bail() noreturn {
    @panic("failed to initialize sdl");
}

pub fn init(allocator: std.mem.Allocator) !Self {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        @panic("SDL_Init failed");
    }

    const window = c.SDL_CreateWindow("dazed emu", dims.real_width / 2, dims.real_height / 2, c.SDL_WINDOW_RESIZABLE) orelse bail();

    const renderer = c.SDL_CreateRenderer(window, null) orelse bail();

    if (!c.SDL_SetRenderVSync(renderer, 1)) {
        @panic("SDL_SetRenderVSync failed");
    }

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_ARGB8888,
        c.SDL_TEXTUREACCESS_STREAMING,
        dims.real_width,
        dims.real_height,
    ) orelse bail();

    const pixels = try allocator.alloc(u32, dims.real_width * dims.real_height);
    @memset(pixels, 0);

    var buffers: [dims.frame_count][]u8 = undefined;
    for (0..dims.frame_count) |i| {
        buffers[i] = try allocator.alloc(u8, dims.frame_size);
        @memcpy(buffers[i], BlankFrame.get());
    }

    return Self{
        .allocator = allocator,
        .window = window,
        .renderer = renderer,
        .texture = texture,
        .pixels = pixels,
        .buffers = buffers,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.pixels);
    for (0..dims.frame_count) |i| {
        self.allocator.free(self.buffers[i]);
    }

    c.SDL_DestroyTexture(self.texture);
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit();
}

pub fn waitForExit(self: *Self) void {
    _ = self;
    var exit = false;
    while (!exit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => exit = true,
                else => {},
            }
        }
    }
}

pub fn pageFlip(self: *Self) !void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        switch (event.type) {
            // Ok, I know this is dirty but whatever
            c.SDL_EVENT_QUIT => return error.Quit,
            else => {},
        }
    }

    // I guess we don't actually want to clear anything. I'm leaving this here for debugging
    if (false) {
        if (!c.SDL_SetRenderDrawColor(self.renderer, 20, 20, 20, 255)) {
            @panic("SDL_RenderClearColor failed");
        }
        if (!c.SDL_RenderClear(self.renderer)) {
            @panic("SDL_RenderClear failed");
        }
    }

    self.translateFrameToTexture(self.getBackBuffer());

    if (!c.SDL_RenderTextureRotated(self.renderer, self.texture, null, null, 0, null, c.SDL_FLIP_VERTICAL)) {
        @panic("SDL_RenderCopy failed");
    }

    if (!c.SDL_RenderPresent(self.renderer)) {
        @panic("SDL_RenderPresent failed");
    }

    self.front_buffer_index = @intCast(self.back_buffer_index);
    // TODO: waved uses % 2 here, but let's try and % frame_count
    self.back_buffer_index = (self.back_buffer_index + 1) % 2;
}

fn translateFrameToTexture(self: *Self, frame: []const u8) void {
    const pixels: [*]u32 = p:{
        var result: *anyopaque = undefined;
        var pitch: c_int = 0;
        if (!c.SDL_LockTexture(self.texture, null, @ptrCast(&result), &pitch)) {
            @panic("SDL_LockTexture failed");
        }
        std.debug.assert(dims.real_width * @sizeOf(u32) == pitch);

        break :p @alignCast(@ptrCast(result));
    };

    // Skip margins
    const data_ptr = frame.ptr + dims.upper_margin * dims.stride + dims.left_margin * dims.depth;

    var y: usize = 0;
    while (y < dims.real_height) : (y += 1) {
        // Get pointer to the start of this row of packed pixel data
        var row_ptr = data_ptr + y * dims.stride;

        // Process each packed pixel group in the row
        var x: usize = 0;
        while (x < dims.real_width) : (x += dims.packed_pixels) {
            // Read the packed phases
            const phases = std.mem.readInt(u16, row_ptr[0..2], .little);
            row_ptr += dims.depth;

            // Unpack and process each phase
            var j: u32 = 0;
            while (j < dims.packed_pixels and x + j < dims.real_width) : (j += 1) {
                // Extract 2-bit phase from the packed value (starting from MSB)
                const shift: u4 = @intCast((dims.packed_pixels - 1 - j) * 2);
                const phase: u8 = @intCast((phases >> shift) & 0b11);

                // Get pixel index once
                const pixel_idx = y * dims.real_width + (x + j);
                const pixel_val = self.pixels[pixel_idx];

                // Extract grayscale value once (assuming RGB are the same)
                const gray_val: i16 = @intCast(pixel_val & 0xFF);

                const single_frame_change = 22;
                const new_val: u32 = @intCast(switch (phase) {
                    @intFromEnum(Waveform.Phase.Black) => @max(0, gray_val - single_frame_change),
                    @intFromEnum(Waveform.Phase.White) => @min(255, gray_val + single_frame_change),
                    else => gray_val,
                });

                pixels[pixel_idx] = (0xFF << 24) | (new_val << 16) | (new_val << 8) | new_val;
            }
        }
    }

    @memcpy(self.pixels, pixels);
    c.SDL_UnlockTexture(self.texture);
}

pub fn getTemperature(self: *Self) !i32 {
    _ = self;
    return 20;
}

pub fn getBackBuffer(self: *Self) []u8 {
    const result = self.buffers[self.back_buffer_index];
    std.debug.assert(result.len == dims.frame_size);

    return result;
}
