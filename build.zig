const std = @import("std");
const ZXGBuild = @import("./build/zxg.zig");

pub fn setup(
    b: *std.Build,
    targetBuild: *std.Build,
    exe: *std.Build.Step.Compile,
    options: ZXGBuild.ZXGBuildInitOptions,
) void {
    var zxgBuild = ZXGBuild.init(b, targetBuild, options);
    zxgBuild.setup(exe);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var zxgBuild = ZXGBuild.init(b, b, .{
        .target = target,
        .optimize = optimize,
        //.mustacheVariables = b.addOptions(),
    });

    const zxgModule = b.addModule("zxg", .{
        .root_source_file = b.path("src/zxg.zig"),
        .target = target,
        .optimize = optimize,
    });

    zxgBuild.addClayXmlModuleImports(zxgModule);

    const exe = b.addExecutable(.{
        .name = "zxg-example",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    zxgBuild.setup(exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
