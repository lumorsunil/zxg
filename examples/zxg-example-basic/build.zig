const std = @import("std");

const zxg = @import("zxg");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zxg-example-basic",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zxgDep = b.dependency("zxg", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zxg", zxgDep.module("zxg"));

    zxg.setup(zxgDep.builder, b, exe, .{
        .target = target,
        .optimize = optimize,
        .layoutPath = "layout.xml",
        .generatedLayoutImport = "generated-layout",
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
