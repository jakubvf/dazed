const std = @import("std");

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
    try display.flush();

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

    while (true) {
        const bytes_read = try touch_input_file.read(std.mem.asBytes(&event));
        if (bytes_read == 0) {
            std.log.err("bytes_read = 0, quitting", .{});
            return;
        }

        if (bytes_read != @sizeOf(InputEvent)) {
            std.log.err("Short read {}b, expected {}b", .{ bytes_read, @sizeOf((InputEvent)) });
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
            // Flush every few frames to batch drawing operations
            frame_counter += 1;
            if (frame_counter % 5 == 0) {
                try display.flush();
            }
        }
    }
}
