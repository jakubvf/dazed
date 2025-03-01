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

pub fn init(
    width: u32,
    depth: u32,
    packed_pixels: u32,
    height: u32,
    frame_count: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
) @This() {
    const stride = width * depth;
    const frame_size = stride * height;
    const real_width = (width - left_margin - right_margin) * packed_pixels;
    const real_height = (height - upper_margin - lower_margin);
    return .{
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

pub fn rm2() @This() {
    return @This().init(260, 4, 8, 1408, 17, 26, 0, 3, 1);
}
