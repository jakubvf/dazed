const std = @import("std");

const FramebufferDimensions = @import("framebuffer_dimensions.zig");
const BlankFrame = @import("blank_frame.zig");


const log = std.log.scoped(.Controller);
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("linux/fb.h");
    @cInclude("string.h");
    @cInclude("errno.h");
});
const fb_var_screeninfo = c.struct_fb_var_screeninfo;
const fb_fix_screeninfo = c.struct_fb_fix_screeninfo;


const Controller = @This();

framebuffer_fd: std.fs.File,
temp_sensor_fd: std.fs.File,

last_temperature_read: ?i64 = null,
temperature: i32 = undefined,

front_buffer_index: i8 = -1,

dims: FramebufferDimensions,

power_state: bool = false,

fb_var_info: fb_var_screeninfo = undefined,
fb_fix_info: fb_fix_screeninfo = undefined,

framebuffer: ?[]u8 = null,

back_buffer_index: u8 = 0,

pub fn init(allocator: std.mem.Allocator) !Controller {
    _ = allocator;
    // "mxs-lcdif",
    const framebuffer_path = "/dev/fb0";

    // "sy7636a_temperature",
    const temp_sesnor_path = "/sys/class/hwmon/hwmon1/temp0";

    log.info(
        "Initializing controller:\n framebuffer: {s}\n temperature sensor: {s}",
        .{
            framebuffer_path,
            temp_sesnor_path,
        },
    );

    const dims = FramebufferDimensions.init(260, 4, 8, 1408, 17, 26, 0, 3, 1);

    var result =  Controller{
        .framebuffer_fd = try std.fs.openFileAbsolute(framebuffer_path, .{ .mode = .read_write }),
        .temp_sensor_fd = try std.fs.openFileAbsolute(temp_sesnor_path, .{ .mode = .read_only }),
        .dims = dims,
    };

    try result.start();

    return result;
}

pub fn deinit(self: *Controller) void {
    if (self.power_state) {
        self.stop();
    }

    self.framebuffer_fd.close();
    self.temp_sensor_fd.close();
}

pub fn start(self: *Controller) !void {
    log.info("Starting controller", .{});
    self.setPower(true);
    _ = try self.getTemperature();

    const FBIOGET_VSCREENINFO = 0x4600;
    const result = std.os.linux.ioctl(self.framebuffer_fd.handle, FBIOGET_VSCREENINFO, @intFromPtr(&self.fb_var_info));
    if (result == -1) {
        log.err("ioctl FBIOGET_VSCREENINFO failed", .{});
        return error.ControllerInitFailed;
    }

    const FBIOGET_FSCREENINFO = 0x4602;
    if (std.os.linux.ioctl(self.framebuffer_fd.handle, FBIOGET_FSCREENINFO, @intFromPtr(&self.fb_fix_info)) == -1) {
        log.err("ioctl FBIOGET_FSCREENINFO failed", .{});
        return error.ControllerInitFailed;
    }

    if (self.fb_var_info.xres != self.dims.width or self.fb_var_info.yres != self.dims.height or self.fb_var_info.xres_virtual != self.dims.width or self.fb_var_info.yres_virtual != self.dims.height * self.dims.frame_count or self.fb_fix_info.smem_len < self.dims.total_size) {
        log.err(
            \\Framebuffer dimensions do not match:
            \\ xres: {d} (expected: {d})
            \\ yres: {d} (expected: {d})
            \\ xres_virtual: {d} (expected: {d})
            \\ yres_virtual: {d} (expected: {d})
            \\ smem_len: {d} (expected: {d})
        , .{
            self.fb_var_info.xres,
            self.dims.width,
            self.fb_var_info.yres,
            self.dims.height,
            self.fb_var_info.xres_virtual,
            self.dims.width,
            self.fb_var_info.yres_virtual,
            self.dims.height * self.dims.frame_count,
            self.fb_fix_info.smem_len,
            self.dims.total_size,
        });
        return error.ControllerInitFailed;
    }

    log.debug("mmaping framebuffer", .{});
    // Map framebuffer to memory
    const mmap_result = std.os.linux.mmap(
        null,
        self.fb_fix_info.smem_len,
        std.os.linux.PROT.READ | std.os.linux.PROT.WRITE,
        std.os.linux.MAP{ .TYPE = .SHARED },
        self.framebuffer_fd.handle,
        0,
    );
    if (mmap_result > std.math.maxInt(isize)) {
        log.err("Map framebuffer to memory failed", .{});
        return error.ControllerInitFailed;
    }

    self.framebuffer = @as(*[]u8, @constCast(@ptrCast(&.{ .ptr = @as([*]u8, @ptrFromInt(mmap_result)), .len = self.fb_fix_info.smem_len }))).*;

    var frame_i: usize = 0;
    while (frame_i < self.dims.frame_count) : (frame_i += 1) {
        const begin = frame_i * self.dims.frame_size;
        const end = begin + self.dims.frame_size;
        const dest = self.framebuffer.?[begin..end];
        @memcpy(dest, BlankFrame.get());
    }
}

pub fn stop(self: *Controller) void {
    log.info("Stopping controller", .{});
    if (self.framebuffer) |fb| {
        _ = std.os.linux.munmap(@ptrCast(fb.ptr), self.fb_fix_info.smem_len);
        self.framebuffer = null;
    }
    self.setPower(false);
}

pub fn getTemperature(self: *Controller) !i32 {
    const temperature_read_interval = 30; //seconds

    const now = std.time.timestamp();
    if (self.last_temperature_read == null or now - self.last_temperature_read.? > temperature_read_interval and self.power_state) {
        var buffer: [12]u8 = undefined;
        try self.temp_sensor_fd.seekTo(0);
        const n = try self.temp_sensor_fd.read(&buffer);
        if (n == 0) return error.ControllerTemperatureReadFailed;

        self.temperature = try std.fmt.parseInt(u8, buffer[0 .. n - 1], 10);
        self.last_temperature_read = now;
        log.info("Temperature is {}", .{self.temperature});
    }

    return self.temperature;
}

pub fn setPower(self: *Controller, value: bool) void {
    const FBIOBLANK = 0x4611;
    const FBIOBLANK_OFF = 4;
    const FBIOBLANK_ON = 0;

    if (value != self.power_state) {
        if (std.os.linux.ioctl(self.framebuffer_fd.handle, FBIOBLANK, if (value) FBIOBLANK_ON else FBIOBLANK_OFF) == 0) {
            self.power_state = value;
        } else {
            @panic("ioctl FBIOBLANK failed");
        }
    }
    if (!self.power_state) {
        self.front_buffer_index = -1;
    }
}

pub fn getBackBuffer(self: *Controller) []u8 {
    if (self.framebuffer == null) {
        @panic("Controller is not initialized");
    }
    const result = self.framebuffer.?[self.back_buffer_index * self.dims.frame_size .. (self.back_buffer_index + 1) * self.dims.frame_size];
    std.debug.assert(result.len == self.dims.frame_size);

    return result;
}

pub fn pageFlip(self: *Controller) !void {
    if (self.framebuffer == null) {
        @panic("Controller is not initialized");
    }

    self.fb_var_info.yoffset = self.back_buffer_index * self.dims.height;

    // Schedule first frame
    const FBIOPUT_VSCREENINFO = 0x4601;
    // Schedule next frame to be displayed and wait for vsync
    const FBIOPAN_DISPLAY = 0x4606;
    const request: u32 = if (self.front_buffer_index == -1) FBIOPUT_VSCREENINFO else FBIOPAN_DISPLAY;

    const result = std.os.linux.ioctl(self.framebuffer_fd.handle, request, @intFromPtr(&self.fb_var_info));

    if (result > std.math.maxInt(isize)) {
        const err: c_int = @intCast(-@as(i32, @bitCast(result)));
        log.err("ioctl failed with errno {}: {s}", .{ err, c.strerror(err) });
        return error.ControllerPageFlipFailed;
    }

    self.front_buffer_index = @intCast(self.back_buffer_index);
    // TODO: waved uses % 2 here, but let's try and % frame_count
    self.back_buffer_index = (self.back_buffer_index + 1) % 2;
}

pub fn waitForExit(self: *Controller) void {
    _ = self;
    return;
}
