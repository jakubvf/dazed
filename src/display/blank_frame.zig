//
// This is a GLOBAL VARIABLE
// Maybe this isn't ideal, but I'll come up with something better once this bites me back in the future.
//

const std = @import("std");
const FramebufferDimensions = @import("framebuffer_dimensions.zig");
const dims = FramebufferDimensions.rm2();

// TODO: It's dangerous to leave this undefined, but for now, let's just roll with it.
var blank_frame:[] const u8 = undefined;
var initialized = false;

pub fn get() []const u8 {
    if (!initialized) @panic("blank_frame not initialized!");

    return blank_frame;
}

pub fn init(allocator: std.mem.Allocator) void {
    if (initialized) return;

    const result = allocator.alloc(u8, dims.frame_size) catch @panic("could not allocate blank_frame");

    for (result) |*v| {
        v.* = 0x0;
    }

    // Frame sync flag constants
    const frame_sync: u8 = 0x1;
    const frame_begin: u8 = 0x2;
    const frame_data: u8 = 0x4;
    const frame_end: u8 = 0x8;
    _ = frame_end;
    const line_sync: u8 = 0x10;
    const line_begin: u8 = 0x20;
    const line_data: u8 = 0x40;
    const line_end: u8 = 0x80;
    _ = line_end;

    // Get pointer to the third byte of the blank frame
    var data: [*]u8 = result.ptr + 2;

    // First line
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        data[0] = frame_sync | frame_begin | line_data;
        data += dims.depth;
    }
    i = 0;
    while (i < 20) : (i += 1) {
        data[0] = frame_sync | frame_begin | frame_data | line_data;
        data += dims.depth;
    }
    i = 0;
    while (i < 63) : (i += 1) {
        data[0] = frame_sync | frame_data | line_data;
        data += dims.depth;
    }
    i = 0;
    while (i < 40) : (i += 1) {
        data[0] = frame_sync | frame_begin | frame_data | line_data;
        data += dims.depth;
    }
    i = 0;
    while (i < 117) : (i += 1) {
        data[0] = frame_sync | frame_begin | line_data;
        data += dims.depth;
    }

    // Second and third lines
    var y: usize = 1;
    while (y < 3) : (y += 1) {
        i = 0;
        while (i < 8) : (i += 1) {
            data[0] = frame_sync | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 11) : (i += 1) {
            data[0] = frame_sync | line_begin | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 36) : (i += 1) {
            data[0] = frame_sync | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 200) : (i += 1) {
            data[0] = frame_sync | frame_begin | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 5) : (i += 1) {
            data[0] = frame_sync | line_data;
            data += dims.depth;
        }
    }

    // Following lines
    y = 3;
    while (y < dims.height) : (y += 1) {
        i = 0;
        while (i < 8) : (i += 1) {
            data[0] = frame_sync | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 11) : (i += 1) {
            data[0] = frame_sync | line_begin | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 7) : (i += 1) {
            data[0] = frame_sync | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 29) : (i += 1) {
            data[0] = frame_sync | line_sync | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 200) : (i += 1) {
            data[0] = frame_sync | frame_begin | line_sync | line_data;
            data += dims.depth;
        }
        i = 0;
        while (i < 5) : (i += 1) {
            data[0] = frame_sync | line_sync | line_data;
            data += dims.depth;
        }
    }

    blank_frame = result;

    initialized = true;
}


pub fn deinit(allocator: std.mem.Allocator) void {
    allocator.free(blank_frame);
}
