const std = @import("std");
const Module = std.Build.Module;
const Compile = std.Build.Step.Compile;
const Dependency = std.Build.Dependency;

const ZXGBuild = @This();

pub const ZXGBuildInitOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    layoutPath: []const u8 = "layout.xml",
    generatedLayoutImport: []const u8 = "generated-layout",
    //mustacheVariables: *std.Build.Step.Options,
};

b: *std.Build,
targetBuild: *std.Build,
options: ZXGBuildInitOptions,
mustacheGen: *Compile,
xmlGen: *Compile,
mustacheDep: *Dependency,
clayDep: *Dependency,
raylibDep: *Dependency,
uuidDep: *Dependency,

pub fn init(b: *std.Build, targetBuild: *std.Build, options: ZXGBuildInitOptions) ZXGBuild {
    return ZXGBuild{
        .b = b,
        .targetBuild = targetBuild,
        .options = options,
        .mustacheGen = b.addExecutable(.{
            .name = "mustache-gen",
            .root_source_file = b.path("tools/mustache-gen.zig"),
            .target = b.host,
        }),
        .xmlGen = b.addExecutable(.{
            .name = "xml-gen",
            .root_source_file = b.path("tools/xml-gen.zig"),
            .target = b.host,
        }),
        .mustacheDep = b.dependency("mustache", .{
            .target = b.host,
        }),
        .clayDep = b.dependency("clay-zig", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
        .raylibDep = b.dependency("raylib-zig", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
        .uuidDep = b.dependency("uuid", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
    };
}

pub fn addClayXmlModuleImports(self: *ZXGBuild, module: *Module) void {
    module.addImport("clay", self.clayDep.module("clay"));
    module.addImport("clay_renderer", self.clayDep.module("renderer_raylib"));
    module.addImport("raylib", self.raylibDep.module("raylib"));
    module.addImport("raygui", self.raylibDep.module("raygui"));
}

pub fn setup(self: *ZXGBuild, exe: *Compile) void {
    //self.mustacheGen.root_module.addImport("mustache", self.mustacheDep.module("mustache"));
    ////self.mustacheGen.root_module.addAnonymousImport("variables", .{ .root_source_file = self.b.path("config/layout-variables.zig") });
    //self.mustacheGen.root_module.addOptions("variables", self.options.mustacheVariables);

    //const mustache_step = self.targetBuild.addRunArtifact(self.mustacheGen);
    //mustache_step.addFileArg(self.targetBuild.path(self.options.layoutPath));
    //const mustache_output = mustache_step.addOutputFileArg("generated-layout.clay");

    //self.xmlGen.root_module.addAnonymousImport("layout", .{ .root_source_file = self.targetBuild.path(self.options.layoutPath) });
    self.xmlGen.root_module.addImport("uuid", self.uuidDep.module("uuid"));

    const xmlGen_step = self.targetBuild.addRunArtifact(self.xmlGen);
    xmlGen_step.addFileArg(self.targetBuild.path(self.options.layoutPath));
    const xmlGen_output = xmlGen_step.addOutputFileArg("generated-layout.zig");
    const generatedLayoutModule = self.targetBuild.addModule("generated-layout", .{
        .root_source_file = xmlGen_output,
        .target = self.options.target,
        .optimize = self.options.optimize,
    });
    exe.root_module.addImport(self.options.generatedLayoutImport, generatedLayoutModule);

    exe.linkLibrary(self.clayDep.artifact("clay"));
    generatedLayoutModule.addImport("raylib", self.raylibDep.module("raylib"));
    generatedLayoutModule.addImport("clay", self.clayDep.module("clay"));
    exe.root_module.addImport("clay", self.clayDep.module("clay"));

    const cl = @import("clay-zig");
    cl.enableRaylibRenderer(exe, self.clayDep, self.raylibDep);

    const raylib = self.raylibDep.module("raylib"); // main raylib module
    const raygui = self.raylibDep.module("raygui"); // raygui module
    const raylib_artifact = self.raylibDep.artifact("raylib"); // raylib C library

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);
}
