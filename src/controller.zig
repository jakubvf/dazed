// Specifies the framebuffer dimensions and margins.
const FramebufferDimensions = struct {
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
        return FramebufferDimensions{
            .width = width,
            .height = height,
            .stride = width * depth,
            .packed_pixels = packed_pixels,
            .depth = depth,
            .frame_size = .stride * height,
            .frame_count = frame_count,
            .total_size = .frame_size * frame_count,
            .left_margin = left_margin,
            .right_margin = right_margin,
            .upper_margin = upper_margin,
            .lower_margin = lower_margin,
            .real_width = (width - left_margin - right_margin) * packed_pixels,
            .real_height = (height - upper_margin - lower_margin),
            .real_size = .real_width * .real_height,
        };
    }
};

const Controller = struct {
    fn openRemarmable2() Controller {
        return byName(
        "mxs-lcdif",
        "sy7636a_temperature",
        FramebufferDimensions.init(
            260,
            4,
            8,
            1408,
            17,
            26,
            0,
            3,
            1
        )
        );
    }
};
