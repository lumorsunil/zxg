const std = @import("std");
const Module = std.Build.Module;
const Compile = std.Build.Step.Compile;
const Dependency = std.Build.Dependency;
const LazyPath = std.Build.LazyPath;

const cl = @import("clay-zig");

const ZXGBuild = @This();

pub const ZXGBackend = enum {
    Clay,
    Dvui,
    Zgui,
    NotSpecified,
};

pub const ZXGBuildInitOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    layoutPath: []const u8 = "layout.xml",
    generatedLayoutImport: []const u8 = "generated-layout",
    backend: ZXGBackend,
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
dvuiDep: *Dependency,
zguiDep: *Dependency,
rlimguiDep: *Dependency,
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
        .dvuiDep = b.dependency("dvui", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
        .zguiDep = b.dependency("zgui", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
        .rlimguiDep = b.dependency("rlimgui", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
        .uuidDep = b.dependency("uuid", .{
            .target = options.target,
            .optimize = options.optimize,
        }),
    };
}

pub fn raylibModule(self: *ZXGBuild) *Module {
    return self.raylibDep.module("raylib");
}

pub fn raylibGuiModule(self: *ZXGBuild) *Module {
    return self.raylibDep.module("raygui");
}

pub fn clayModule(self: *ZXGBuild) *Module {
    return self.clayDep.module("clay");
}

pub fn clayRendererModule(self: *ZXGBuild) *Module {
    return self.clayDep.module("renderer_raylib");
}

pub fn dvuiModule(self: *ZXGBuild) *Module {
    return self.dvuiDep.module("dvui_raylib");
}

pub fn zguiModule(self: *ZXGBuild) *Module {
    return self.zguiDep.module("root");
}

fn getXmlGenOptions(self: *ZXGBuild) *std.Build.Step.Options {
    var xmlGenOptions = self.b.addOptions();
    xmlGenOptions.addOption(ZXGBackend, "backend", self.options.backend);
    return xmlGenOptions;
}

const SetupBackendOptions = struct {
    includeArtifacts: bool,
    linkLibCpp: bool,
};

pub fn setupBackend(self: *ZXGBuild, module: *Module, options: SetupBackendOptions) void {
    if (options.includeArtifacts) module.linkLibrary(self.raylibDep.artifact("raylib"));
    module.addImport("raylib", self.raylibModule());
    module.addImport("raygui", self.raylibGuiModule());

    switch (self.options.backend) {
        .Clay => {
            if (options.includeArtifacts) module.linkLibrary(self.clayDep.artifact("clay"));
            module.addImport("clay", self.clayModule());
            module.addImport("clay_renderer", self.clayRendererModule());
        },
        .Dvui => {
            module.addImport("dvui", self.dvuiModule());
        },
        .Zgui => {
            if (options.linkLibCpp) {
                module.link_libcpp = true;
            }
            if (options.includeArtifacts) {
                module.linkLibrary(self.zguiDep.artifact("imgui"));
            }
            module.addImport("zgui", self.zguiModule());
            module.addIncludePath(self.zguiDep.path("libs/imgui"));
            module.addCSourceFile(.{
                .file = self.rlimguiDep.path("rlImGui.cpp"),
                .flags = &.{
                    "-fno-sanitize=undefined",
                    "-std=c++11",
                    "-Wno-deprecated-declarations",
                    "-DNO_FONT_AWESOME",
                },
            });
            module.addIncludePath(self.rlimguiDep.path("."));
        },
        .NotSpecified => {},
    }
}

fn setupXmlGen(self: *ZXGBuild) LazyPath {
    //self.xmlGen.root_module.addAnonymousImport("layout", .{ .root_source_file = self.targetBuild.path(self.options.layoutPath) });
    self.xmlGen.root_module.addImport("uuid", self.uuidDep.module("uuid"));

    self.setupBackend(&self.xmlGen.root_module, .{ .includeArtifacts = true, .linkLibCpp = false });
    self.xmlGen.root_module.addOptions("backend", self.getXmlGenOptions());

    const xmlGen_step = self.targetBuild.addRunArtifact(self.xmlGen);
    xmlGen_step.addFileArg(self.targetBuild.path(self.options.layoutPath));
    return xmlGen_step.addOutputFileArg("generated-layout.zig");
}

fn createGeneratedLayoutModule(self: *ZXGBuild, xmlGen_output: LazyPath) *Module {
    const generatedLayoutModule = self.targetBuild.addModule("generated-layout", .{
        .root_source_file = xmlGen_output,
        .target = self.options.target,
        .optimize = self.options.optimize,
    });

    self.setupBackend(generatedLayoutModule, .{ .includeArtifacts = true, .linkLibCpp = false });

    return generatedLayoutModule;
}

fn exeLinkAndAddImports(self: *ZXGBuild, exe: *Compile, generatedLayoutModule: *Module) void {
    exe.root_module.addImport(self.options.generatedLayoutImport, generatedLayoutModule);
    self.setupBackend(&exe.root_module, .{ .includeArtifacts = true, .linkLibCpp = true });
}

pub fn setup(self: *ZXGBuild, exe: *Compile) void {
    //self.mustacheGen.root_module.addImport("mustache", self.mustacheDep.module("mustache"));
    ////self.mustacheGen.root_module.addAnonymousImport("variables", .{ .root_source_file = self.b.path("config/layout-variables.zig") });
    //self.mustacheGen.root_module.addOptions("variables", self.options.mustacheVariables);

    //const mustache_step = self.targetBuild.addRunArtifact(self.mustacheGen);
    //mustache_step.addFileArg(self.targetBuild.path(self.options.layoutPath));
    //const mustache_output = mustache_step.addOutputFileArg("generated-layout.clay");

    const zxgDep = self.targetBuild.dependency("zxg", .{
        .target = self.options.target,
        .optimize = self.options.optimize,
        .backend = self.options.backend,
    });
    const zxgModule = zxgDep.module("zxg");
    self.setupBackend(zxgModule, .{ .includeArtifacts = true, .linkLibCpp = false });
    exe.root_module.addImport("zxg", zxgModule);

    self.setupNonMainZxgStuff(exe);
}

pub fn setupNonMainZxgStuff(self: *ZXGBuild, exe: *Compile) void {
    const xmlGenOutput = self.setupXmlGen();
    const generatedLayoutModule = self.createGeneratedLayoutModule(xmlGenOutput);

    if (self.options.backend == .Clay) {
        cl.enableRaylibRenderer(exe, self.clayDep, self.raylibDep);
    }

    self.exeLinkAndAddImports(exe, generatedLayoutModule);
}
