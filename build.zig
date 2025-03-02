const std = @import("std");
const ZXGBuild = @import("./build/zxg.zig");
const ZXGBackend = ZXGBuild.ZXGBackend;

pub fn setup(
    targetBuild: *std.Build,
    exe: *std.Build.Step.Compile,
    options: ZXGBuild.ZXGBuildInitOptions,
) ZXGBuild {
    const zxgDep = targetBuild.dependency("zxg", .{
        .target = options.target,
        .optimize = options.optimize,
        .backend = options.backend,
    });
    var zxgBuild = ZXGBuild.init(zxgDep.builder, targetBuild, options);
    zxgBuild.setup(exe);
    return zxgBuild;
}

fn getZXGBuildOptions(backend: ZXGBackend, extraOptions: anytype) ZXGBuild.ZXGBuildInitOptions {
    return ZXGBuild.ZXGBuildInitOptions{
        .target = extraOptions.target,
        .optimize = extraOptions.optimize,
        .backend = backend,
        .layoutPath = extraOptions.layoutPath,
        .generatedLayoutImport = extraOptions.generatedLayoutImport,
    };
}

fn getZXGBuild(b: *std.Build, backend: ZXGBackend, extraOptions: anytype) ZXGBuild {
    return ZXGBuild.init(b, b, getZXGBuildOptions(backend, extraOptions));
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const backend = b.option(ZXGBackend, "backend", "Clay or Dvui") orelse .NotSpecified;
    const layoutPath = b.option([]const u8, "layoutPath", "/path/to/layout.xml") orelse "layout.xml";
    const generatedLayoutImport = b.option([]const u8, "generatedLayoutImport", "import name of generated layout") orelse "generated-layout";

    const extraOptions = .{
        .target = target,
        .optimize = optimize,
        .layoutPath = layoutPath,
        .generatedLayoutImport = generatedLayoutImport,
    };

    std.log.debug("Building zxg with backend {s}", .{@tagName(backend)});

    const zxgModule = b.addModule("zxg", .{
        .root_source_file = b.path("src/zxg.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zxgModuleBackendOptions = b.addOptions();
    zxgModuleBackendOptions.addOption(ZXGBackend, "backend", backend);
    zxgModule.addOptions("backend", zxgModuleBackendOptions);

    var zxgBuild = getZXGBuild(b, backend, extraOptions);

    const implName = switch (backend) {
        .Clay => "clay",
        .Dvui => "dvui",
        .Zgui => "zgui",
        .NotSpecified => "clay",
    };
    const implModule = b.addModule("zxg-" ++ implName, .{
        .root_source_file = b.path("src/zxg-" ++ implName ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });
    zxgModule.addImport("zxg-" ++ implName, implModule);
    zxgBuild.setupBackend(implModule, .{ .includeArtifacts = true, .linkLibCpp = false });
}
