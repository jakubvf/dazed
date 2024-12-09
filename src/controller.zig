const std = @import("std");

// Specifies the framebuffer dimensions and margins.
pub const FramebufferDimensions = struct {
    // Number of pixels in a frame line
    width: u32,

    // Number of bytes per frame pixel
    depth: u32,

    // Number of bytes per frame line
    stride: u32,

    // Number of actual pixels packed inside a frame pixel
    packed_pixels: u32,

    // Number of lines in a frame of the framebuffer
    height: u32,

    // Number of bytes per frame
    frame_size: u32,

    // Number of frames allocated in the framebuffer
    frame_count: u32,

    // Number of available bytes in the framebuffer
    total_size: u32,

    // Blanking margins in each frame
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,

    // Number of usable pixels in a line
    real_width: u32,

    // Number of usable lines in a frame
    real_height: u32,

    // Number of usable pixels in a frame
    real_size: u32,

    fn init(
        width: u32,
        depth: u32,
        packed_pixels: u32,
        height: u32,
        frame_count: u32,
        left_margin: u32,
        right_margin: u32,
        upper_margin: u32,
        lower_margin: u32,
    ) FramebufferDimensions {
        const stride = width * depth;
        const frame_size = stride * height;
        const real_width = (width - left_margin - right_margin) * packed_pixels;
        const real_height = (height - upper_margin - lower_margin);
        return FramebufferDimensions{
            .width = width,
            .height = height,
            .stride = stride,
            .packed_pixels = packed_pixels,
            .depth = depth,
            .frame_size = frame_size,
            .frame_count = frame_count,
            .total_size = frame_size * frame_count,
            .left_margin = left_margin,
            .right_margin = right_margin,
            .upper_margin = upper_margin,
            .lower_margin = lower_margin,
            .real_width = real_width,
            .real_height = real_height,
            .real_size = real_width * real_height,
        };
    }
};

const Bitfield = packed struct {
    offset: u32,
    length: u32,
    msb_right: u32,
};

const VarScreenInfo = packed struct {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,

    bits_per_pixel: u32,
    grayscale: u32,

    red: Bitfield,
    green: Bitfield,
    blue: Bitfield,
    transp: Bitfield,

    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,

    // Timing values in pixclocks, except pixclock
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: u128,
};

const FixScreenInfo = packed struct {
    id: u128,
    smem_start: usize,
    smem_len: u32,
    type: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: usize,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: u32,
};

const log = std.log.scoped(.Controller);

pub const Controller = struct {
    dims: FramebufferDimensions,

    framebuffer_fd: std.fs.File,
    temp_sensor_fd: std.fs.File,

    last_temperature_read: ?i64 = null,
    temperature: i32 = undefined,

    front_buffer_index: i8 = -1,

    power_state: bool = false,

    fb_var_info: VarScreenInfo = undefined,
    fb_fix_info: FixScreenInfo = undefined,

    framebuffer: ?[]u8 = null,

    blank_frame: []u8 = undefined,

    back_buffer_index: usize = 0,

    pub fn init() !Controller {
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

        return Controller{
            .framebuffer_fd = try std.fs.openFileAbsolute(framebuffer_path, .{ .mode = .read_write }),
            .temp_sensor_fd = try std.fs.openFileAbsolute(temp_sesnor_path, .{ .mode = .read_only }),
            .dims = dims,
        };
    }

    pub fn start(self: *Controller, allocator: std.mem.Allocator) !void {
        log.info("Starting controller", .{});
        self.setPower(true);
        _ = try self.getTemperature();

        const FBIOGET_VSCREENINFO = 0x4600;
        if (std.os.linux.ioctl(self.framebuffer_fd.handle, FBIOGET_VSCREENINFO, @intFromPtr(&self.fb_var_info)) == -1) {
            log.err("ioctl FBIOGET_VSCREENINFO failed", .{});
            return error.ControllerInitFailed;
        }

        // Zig has to be f*cking with me. The next ioctl call changes the value of self.dims.
        // Or I am just stupid.
        // debug(Controller): controller.FramebufferDimensions{ .width = 260, .depth = 4, .stride = 1040, .packed_pixels = 8, .height = 1408, .frame_size = 1464320, .frame_count = 17, .total_size = 24893440, .left_margin = 26, .right_margin = 0, .upper_margin = 3, .lower_margin = 1, .real_width = 1872, .real_height = 1404, .real_size = 2628288 }
        //
        // debug(Controller): controller.FramebufferDimensions{ .width = 0, .depth = 4, .stride = 1040, .packed_pixels = 8, .height = 1408, .frame_size = 1464320, .frame_count = 17, .total_size = 24893440, .left_margin = 26, .right_margin = 0, .upper_margin = 3, .lower_margin = 1, .real_width = 1872, .real_height = 1404, .real_size = 2628288 }
        //
        // error(Controller): Framebuffer dimensions do not match:
        // xres: 260 (expected: 0)
        // yres: 1408 (expected: 1408)
        // xres_virtual: 260 (expected: 0)
        // yres_virtual: 23936 (expected: 23936)
        // smem_len: 33554432 (expected: 24893440)
        const temp = self.dims;

        const FBIOGET_FSCREENINFO = 0x4602;
        if (std.os.linux.ioctl(self.framebuffer_fd.handle, FBIOGET_FSCREENINFO, @intFromPtr(&self.fb_fix_info)) == -1) {
            log.err("ioctl FBIOGET_FSCREENINFO failed", .{});
            return error.ControllerInitFailed;
        }
        self.dims = temp;

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
        if (mmap_result == -1) {
            log.err("Map framebuffer to memory failed", .{});
            return error.ControllerInitFailed;
        }

        self.framebuffer = @as(*[]u8, @constCast(@ptrCast(&.{ .ptr = @as([*]u8, @ptrFromInt(mmap_result)), .len = self.fb_fix_info.smem_len }))).*;

        log.debug("creating blank frame", .{});
        // Create blank frame
        self.blank_frame = try allocator.alloc(u8, self.dims.frame_size);
        for (self.blank_frame) |*v| {
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
        var data: [*]u8 = self.blank_frame.ptr + 2;

        // First line
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            data[0] = frame_sync | frame_begin | line_data;
            data += self.dims.depth;
        }
        i = 0;
        while (i < 20) : (i += 1) {
            data[0] = frame_sync | frame_begin | frame_data | line_data;
            data += self.dims.depth;
        }
        i = 0;
        while (i < 63) : (i += 1) {
            data[0] = frame_sync | frame_data | line_data;
            data += self.dims.depth;
        }
        i = 0;
        while (i < 40) : (i += 1) {
            data[0] = frame_sync | frame_begin | frame_data | line_data;
            data += self.dims.depth;
        }
        i = 0;
        while (i < 117) : (i += 1) {
            data[0] = frame_sync | frame_begin | line_data;
            data += self.dims.depth;
        }

        // Second and third lines
        var y: usize = 1;
        while (y < 3) : (y += 1) {
            i = 0;
            while (i < 8) : (i += 1) {
                data[0] = frame_sync | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 11) : (i += 1) {
                data[0] = frame_sync | line_begin | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 36) : (i += 1) {
                data[0] = frame_sync | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 200) : (i += 1) {
                data[0] = frame_sync | frame_begin | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 5) : (i += 1) {
                data[0] = frame_sync | line_data;
                data += self.dims.depth;
            }
        }

        // Following lines
        y = 3;
        while (y < self.dims.height) : (y += 1) {
            i = 0;
            while (i < 8) : (i += 1) {
                data[0] = frame_sync | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 11) : (i += 1) {
                data[0] = frame_sync | line_begin | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 7) : (i += 1) {
                data[0] = frame_sync | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 29) : (i += 1) {
                data[0] = frame_sync | line_sync | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 200) : (i += 1) {
                data[0] = frame_sync | frame_begin | line_sync | line_data;
                data += self.dims.depth;
            }
            i = 0;
            while (i < 5) : (i += 1) {
                data[0] = frame_sync | line_sync | line_data;
                data += self.dims.depth;
            }
        }

        var frame_i: usize = 0;
        while (frame_i < self.dims.frame_count) : (frame_i += 1) {
            @memcpy(self.framebuffer.?[frame_i * self.dims.frame_size .. frame_i * self.dims.frame_size + self.dims.frame_size], self.blank_frame);
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
        const FBIOBLANK_OFF = 0;
        const FBIOBLANK_ON = 4;

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
        const request = if (self.front_buffer_index == -1) FBIOPUT_VSCREENINFO else FBIOPAN_DISPLAY;

        if (std.os.linux.ioctl(self.framebuffer.handle, request, &self.fb_var_info) == -1) {
            log.err("ioctl FBIOPUT_VSCREENINFO failed", .{});
            return error.ControllerPageFlipFailed;
        }

        self.front_buffer_index = self.back_buffer_index;
        // waved uses % 2 here, but let's try and % frame_count
        self.back_buffer_index = (self.back_buffer_index + 1) % self.dims.frame_count;
    }
};
