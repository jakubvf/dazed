const std = @import("std");

pub fn build(b: *std.Build) void {
    const emulator = b.option(bool, "emulator", "Whether to build for the SDL3 emulator") orelse false;
    const profiling = b.option(bool, "profiling", "Whether to enable profiling") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "emulator", emulator);
    options.addOption(bool, "profiling", profiling);

    const target = t: {
        break :t if (!emulator)
            b.standardTargetOptions(.{
                .default_target = std.Target.Query{
                    .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a7 },
                    .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{std.Target.arm.Feature.neon}),
                    .cpu_arch = .arm,
                    .os_tag = .linux,
                    .abi = .musleabihf,
                },
            })
        else
            b.standardTargetOptions(.{});
    };

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "dazed",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("build_config", options);
    exe.linkLibC();

    const freetype = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(freetype.artifact("freetype"));
    exe.root_module.addImport("freetype", freetype.module("freetype"));

    if (emulator) {
        exe.linkSystemLibrary("SDL3");
    }

    b.installArtifact(exe);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/waveform.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
