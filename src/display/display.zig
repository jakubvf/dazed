const std = @import("std");
const ft = @import("freetype");
const Rect = @import("rect.zig");
const Waveform = @import("waveform.zig");
const Controller = @import("sdl3.zig");
const FramebufferDimensions = @import("framebuffer_dimensions.zig");
const BlankFrame = @import("blank_frame.zig");

const dims = FramebufferDimensions.rm2();

const Self = @This();


pub fn sendInit(self: *Self) !void {
}



pub fn sendRect(self: *Self, rect: Rect) !void {
}


pub fn sendPixel(self: *Self, x: u32, y: u32) !void {
}


pub fn sendText(self: *Self, x: u32, y: u32, text: []const u8) !void {
}
