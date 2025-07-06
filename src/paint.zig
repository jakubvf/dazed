const std = @import("std");
const BuildConfig = @import("build_config");

const FramebufferDimensions = @import("display/framebuffer_dimensions.zig");
const dims = FramebufferDimensions.rm2();
const DrawingContext = @import("display/DrawingContext.zig");
const Rect = @import("display/rect.zig");

pub fn run(allocator: std.mem.Allocator, display: *DrawingContext) !void {
    _ = allocator;
    // Draw a welcome message
    try display.text(100, 100, "Paint Program - Touch to draw!");
    
    // Draw a test rectangle
    const test_rect = Rect{ .x = 200, .y = 200, .width = 100, .height = 50 };
    try display.rectangle(test_rect);
    
    // Flush initial drawing
    try display.flushSync();

    if (BuildConfig.emulator) {
        return runEmulator(display);
    } else {
        return runHardware(display);
    }
}

fn runEmulator(display: *DrawingContext) !void {
    const c = @cImport(@cInclude("SDL3/SDL.h"));
    
    var event: c.SDL_Event = undefined;
    var is_drawing = false;
    var frame_counter: u32 = 0;
    var last_flush_time = std.time.timestamp();
    
    while (true) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    try display.flushSync();
                    return;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        is_drawing = true;
                    }
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        is_drawing = false;
                    }
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    if (is_drawing) {
                        const brush_size = 10;
                        const paint_rect = Rect{ 
                            .x = @max(0, @as(i32, @intFromFloat(event.motion.x)) - brush_size/2), 
                            .y = @max(0, @as(i32, @intFromFloat(event.motion.y)) - brush_size/2), 
                            .width = brush_size, 
                            .height = brush_size 
                        };
                        try display.rectangle(paint_rect);
                        
                        frame_counter += 1;
                        const current_time = std.time.timestamp();
                        
                        // Flush every 10 frames OR every 50ms for better responsiveness
                        if (frame_counter % 10 == 0 or (current_time - last_flush_time) > 50) {
                            try display.flush(); // This is now asynchronous
                            last_flush_time = current_time;
                        }
                    }
                },
                else => {},
            }
        }
        
        // Small delay to prevent busy waiting
        std.Thread.sleep(1000000); // 1ms
    }
}

fn runHardware(display: *DrawingContext) !void {
    // Touchscreen input
    const LinuxInput = (@cImport(@cInclude("linux/input.h")));
    const InputEvent = LinuxInput.input_event;

    const touch_input_file = try std.fs.openFileAbsolute("/dev/input/event2", .{});
    defer touch_input_file.close();

    var event: InputEvent = undefined;
    var current_x: ?i32 = null;
    var current_y: ?i32 = null;
    var is_touching = false;
    var frame_counter: u32 = 0;
    var last_flush_time = std.time.timestamp();

    while (true) {
        const bytes_read = try touch_input_file.read(std.mem.asBytes(&event));
        if (bytes_read == 0) {
            std.log.err("bytes_read = 0, quitting", .{});
            // Ensure final flush before exit
            try display.flushSync();
            return;
        }

        if (bytes_read != @sizeOf(InputEvent)) {
            std.log.err("Short read {}b, expected {}b", .{ bytes_read, @sizeOf((InputEvent)) });
            // Ensure final flush before exit
            try display.flushSync();
            break;
        }

        if (event.type == LinuxInput.EV_ABS) {
            switch (event.code) {
                LinuxInput.ABS_MT_POSITION_X => {
                    // Coordinates are swapped for reMarkable 2 orientation
                    current_y = event.value;
                    
                    // Draw immediately on coordinate update
                    if (is_touching and current_x != null and current_y != null) {
                        const brush_size = 10;
                        // Transform coordinates - invert Y axis
                        const screen_x = current_x.?;
                        const screen_y = @as(i32, @intCast(dims.real_height)) - current_y.?;
                        
                        const paint_rect = Rect{ 
                            .x = @max(0, screen_x - brush_size/2), 
                            .y = @max(0, screen_y - brush_size/2), 
                            .width = brush_size, 
                            .height = brush_size 
                        };
                        try display.rectangle(paint_rect);
                    }
                },
                LinuxInput.ABS_MT_POSITION_Y => {
                    // Coordinates are swapped for reMarkable 2 orientation
                    current_x = event.value;
                    
                    // Draw immediately on coordinate update
                    if (is_touching and current_x != null and current_y != null) {
                        const brush_size = 10;
                        // Transform coordinates - invert Y axis
                        const screen_x = current_x.?;
                        const screen_y = @as(i32, @intCast(dims.real_height)) - current_y.?;
                        
                        const paint_rect = Rect{ 
                            .x = @max(0, screen_x - brush_size/2), 
                            .y = @max(0, screen_y - brush_size/2), 
                            .width = brush_size, 
                            .height = brush_size 
                        };
                        try display.rectangle(paint_rect);
                    }
                },
                LinuxInput.ABS_MT_SLOT => std.debug.print("Slot: {}\n", .{event.value}),
                LinuxInput.ABS_MT_TRACKING_ID => {
                    if (event.value == -1) {
                        is_touching = false;
                    } else {
                        is_touching = true;
                    }
                },
                LinuxInput.ABS_MT_PRESSURE => std.debug.print("Pressure: {}\n", .{event.value}),
                else => {},
            }
        } else if (event.type == LinuxInput.EV_SYN and event.code == LinuxInput.SYN_REPORT) {
            // Flush less frequently to allow more batching and background processing
            frame_counter += 1;
            const current_time = std.time.timestamp();
            
            // Flush every 10 frames OR every 50ms for better responsiveness
            if (frame_counter % 10 == 0 or (current_time - last_flush_time) > 50) {
                try display.flush(); // This is now asynchronous
                last_flush_time = current_time;
            }
        }
    }
    
    // Ensure final flush before function exit
    try display.flushSync();
}
