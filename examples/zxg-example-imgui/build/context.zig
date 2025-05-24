const std = @import("std");

const Build = std.Build;
const Dependency = Build.Dependency;
const Module = Build.Module;
const LazyPath = Build.LazyPath;

const zxg = @import("zxg");

pub fn addModuleImports(targets: []const *Module, source: *const Module) void {
    var it = source.import_table.iterator();
    while (it.next()) |entry| for (targets) |target| target.addImport(entry.key_ptr.*, entry.value_ptr.*);
}

pub const Context = struct {
    deps: struct {},
    modules: struct {
        c: *Module,
    },

    pub fn init(b: *Build, options: anytype) Context {
        const target = options.target;
        const optimize = options.optimize;

        const cModule = b.createModule(.{
            .root_source_file = b.path("lib/c.zig"),
            .target = target,
            .optimize = optimize,
        });
        zxg.setup(b, cModule, .{
            .target = target,
            .optimize = optimize,
            .backend = .Zgui,
        });

        return Context{
            .deps = .{},
            .modules = .{
                .c = cModule,
            },
        };
    }

    fn add(self: Context, comptime key: []const u8, target: *Module) void {
        target.addImport(key, @field(self.modules, key));
    }

    pub fn addC(self: Context, target: *Module) void {
        self.add("c", target);
        addModuleImports(&.{target}, self.modules.c);
    }
};
