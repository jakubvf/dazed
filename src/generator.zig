const std = @import("std");

const Controller = @import("controller.zig").Controller;
const Waveform = @import("waveforms/waveformer2.zig").Waveform;
const Transition = @import("waveforms/waveformer2.zig").Transition;

pub const UpdateRegion = struct {
    top: usize,
    left: usize,
    width: usize,
    height: usize,
};

const Generator = @This();

allocator: std.mem.Allocator,
controller: *Controller,
waveform: *const Waveform,
current_intensity: []u8,
next_intensity: []u8,

const log = std.log.scoped(.Generator);
pub fn init(allocator: std.mem.Allocator, controller: *Controller, waveform: *const Waveform) !Generator {
    log.info("Creating generator", .{});
    const generator = Generator{
        .allocator = allocator,
        .controller = controller,
        .waveform = waveform,
        .current_intensity = try allocator.alloc(u8, controller.dims.real_size),
        .next_intensity = try allocator.alloc(u8, controller.dims.real_size),
    };
    @memset(generator.current_intensity, 0);
    @memset(generator.next_intensity, 0);
    log.debug("Set inital intensity values", .{});

    return generator;
}

pub fn deinit(generator: *Generator) void {
    generator.allocator.free(generator.current_intensity);
    generator.allocator.free(generator.next_intensity);
}

const Intensity = u8;
const intensity_values = 1 << 5;

pub fn update_display(generator: *Generator, buffer: []const u8, region: UpdateRegion) !void {
    log.debug("Updating display", .{});
    const dims = &generator.controller.dims;

    if (buffer.len != region.width * region.height) {
        return error.GeneratorInvalidRegion;
    }

    const transformed_buffer = try generator.allocator.alloc(u8, buffer.len);
    var k: usize = 0;
    while (k < buffer.len) : (k += 1) {
        const i = region.height - (k % region.height) - 1;
        const j = region.width - (k / region.height) - 1;

        transformed_buffer[k] = buffer[i * region.width + j] & (intensity_values - 1);
    }
    log.debug("created transformed buffer", .{});

    const top = dims.real_height - region.left - region.width;
    const left = dims.real_width - region.top - region.height;
    const width = region.height;
    const height = region.width;
    var transformed_region = UpdateRegion{
        .top = top,
        .left = left,
        .height = height,
        .width = width,
    };

    if (transformed_region.left >= dims.real_width or transformed_region.top >= dims.real_height or transformed_region.left + transformed_region.width > dims.real_width or transformed_region.top + transformed_region.height > dims.real_height) {
        log.err("Region out of bounds", .{});
        return error.GeneratorInvalidRegion;
    }

    log.debug("updating intensity buffer", .{});
    generator.updateIntensityBuffer(transformed_buffer, &transformed_region);

    const transition = generator.waveform.lookup(0, try generator.controller.getTemperature()).?;

    log.debug("begin frame generation", .{});
    try generator.generateAndSendFrames(transition, &transformed_region);
}

fn updateIntensityBuffer(generator: *Generator, buffer: []const u8, region: *UpdateRegion) void {
    const dims = &generator.controller.dims;

    const mask = dims.packed_pixels - 1;
    if ((region.width & mask) == 0 and (region.left & mask) == 0) {
        log.debug("region is aligned", .{});
    } else {
        log.debug("aligning region", .{});
        region.left = region.left & ~mask;
        const pad_left = region.left & mask;
        region.width = (pad_left + region.width + mask) & ~mask;
    }

    var y: usize = 0;
    while (y < region.height) : (y += 1) {
        var x: usize = 0;
        while (x < region.width) : (x += 1) {
            const target_idx = (region.top + y) * dims.real_width + (region.left + x);
            const source_idx = y * region.width + x;
            generator.next_intensity[target_idx] = buffer[source_idx];
        }
    }
}

fn generateAndSendFrames(generator: *Generator, waveform: []const Transition, region: *const UpdateRegion) !void {
    const dims = &generator.controller.dims;
    const blank_frame = generator.controller.blank_frame;

    // Find the longest transition sequence in the waveform
    var max_operations: usize = 0;
    for (waveform) |transition| {
        max_operations = @max(max_operations, transition.operations.len);
    }

    // Generate one frame for each step in the longest transition
    var operation_idx: usize = 0;
    while (operation_idx < max_operations) : (operation_idx += 1) {
        log.debug("duplicating frame {}", .{operation_idx});
        const frame = try generator.allocator.dupe(u8, blank_frame);
        const data: [*]u16 = @alignCast(@ptrCast(frame.ptr +
            (dims.upper_margin + region.top) * dims.stride +
            dims.left_margin * dims.depth + // Remove division by packed_pixels here
            (region.left / dims.packed_pixels) * dims.depth // Separate the packed pixels adjustment
        ));

        log.debug("drawing frame", .{});
        var y: usize = 0;
        while (y < region.height) : (y += 1) {
            var x: usize = 0;
            while (x < region.width) : (x += dims.packed_pixels) {
                var packed_phases: u16 = 0;

                var px: usize = 0;
                while (px < dims.packed_pixels and (x + px) < region.width) : (px += 1) {
                    const idx = (region.top + y) * dims.real_width + (region.left + x + px);
                    packed_phases <<= 2;

                    // Get current and target intensities for this pixel
                    const current = generator.current_intensity[idx];
                    _ = current;
                    const target = generator.next_intensity[idx];
                    _ = target;

                    // Find the transition for these intensity values
                    // const transition = waveform[1]; //findTransition(waveform, current, target);

                    // Get the phase for the current operation step
                    // If we're past the end of this transition's operations,
                    // use Noop phase
                    const phase = waveform[1].operations[operation_idx];

                    packed_phases |= @intFromEnum(phase);
                }

                // Write the packed phases for this group of pixels
                const data_idx = y * (dims.stride / @sizeOf(u16)) + (x / dims.packed_pixels);
                data[data_idx] = packed_phases;
            }
        }

        log.debug("copying new frame to backbuffer", .{});
        @memcpy(generator.controller.getBackBuffer(), frame);
        try generator.controller.pageFlip();
    }

    log.debug("copying intensities", .{});
    std.mem.swap([]u8, &generator.current_intensity, &generator.next_intensity);
}

fn findTransition(waveform: []const Transition, from: Intensity, to: Intensity) Transition {
    for (waveform) |transition| {
        if (transition.from == from and transition.to == to) {
            return transition;
        }
    }
    // Should probably have error handling here
    unreachable;
}
