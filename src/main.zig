const std = @import("std");
const BuildConfig = @import("build_config");
const HackerNews = @import("hackernews.zig");
const DrawingContext = @import("display/DrawingContext.zig");
const Waveform = @import("display/waveform.zig");
const ft = @import("freetype");
const BlankFrame = @import("display/blank_frame.zig");
const profiler = @import("profiler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try profiler.initGlobal(allocator);
    defer profiler.deinitGlobal(allocator);

    var prof_scope = profiler.profile("main");
    defer prof_scope.deinit();

    BlankFrame.init(allocator);
    defer BlankFrame.deinit(allocator);

    if (BuildConfig.emulator) {
        const SDL3 = @import("display/sdl3.zig");
        var controller = try SDL3.init(allocator);
        defer controller.deinit();
        
        const display_interface = controller.asInterface();
        var drawing_context = try initDrawingContext(allocator, display_interface);
        defer deinitDrawingContext(&drawing_context, allocator);
        
        try drawing_context.clear();
        return HackerNews.run(allocator, &drawing_context);
    } else {
        const RM2 = @import("display/rm2.zig");
        var controller = try RM2.init(allocator);
        defer controller.deinit();
        
        const display_interface = controller.asInterface();
        var drawing_context = try initDrawingContext(allocator, display_interface);
        defer deinitDrawingContext(&drawing_context, allocator);
        
        try drawing_context.clear();
        return HackerNews.run(allocator, &drawing_context);
    }
}

const DisplayInterface = @import("display/Interface.zig");
fn initDrawingContext(allocator: std.mem.Allocator, display_interface: DisplayInterface) !DrawingContext {
    const wbf_file = if (BuildConfig.emulator) 
        "src/waveforms/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf" 
    else 
        "/usr/share/remarkable/320_R467_AF4731_ED103TC2C6_VB3300-KCD_TC.wbf";
    
    const waveform_table = try Waveform.Table.fromWbf(allocator, wbf_file);
    
    const ft_lib = try ft.Library.init();
    const ft_face = try ft_lib.initMemoryFace(@embedFile("fonts/Roboto_Mono/static/RobotoMono-Bold.ttf"), 0);
    try ft_face.selectCharmap(.unicode);
    
    return DrawingContext{
        .display = display_interface,
        .allocator = allocator,
        .waveform_table = waveform_table,
        .ft_lib = ft_lib,
        .ft_face = ft_face,
    };
}

fn deinitDrawingContext(drawing_context: *DrawingContext, allocator: std.mem.Allocator) void {
    drawing_context.ft_face.deinit();
    drawing_context.ft_lib.deinit();
    drawing_context.waveform_table.deinit(allocator);
}
