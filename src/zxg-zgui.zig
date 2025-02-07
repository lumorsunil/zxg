const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const zgui = @import("zgui");
const c = @cImport({
    @cDefine("NO_FONT_AWESOME", "1");
    @cInclude("rlImGui.h");
});

pub const ZXGZguiApp = struct {
    gpa: GPA = undefined,
    allocator: Allocator = undefined,

    const GPA = std.heap.GeneralPurposeAllocator(.{ .safety = true });

    pub fn init(width: i32, height: i32, comptime title: []const u8) ZXGZguiApp {
        rl.initWindow(width, height, @ptrCast(title));
        rl.setWindowState(.{ .window_resizable = true });
        rl.setTargetFPS(60);
        c.rlImGuiSetup(true);
        zgui.initNoContext(std.heap.c_allocator);

        return ZXGZguiApp{};
    }

    fn alloc(self: *ZXGZguiApp) !void {
        self.gpa = GPA{};
        self.allocator = self.gpa.allocator();
    }

    pub fn loadFont(self: *ZXGZguiApp, fileName: []const u8, fontSize: f32) !void {
        _ = self; // autofix
        // Uncomment this to set a custom font for ImGui.
        const font = zgui.io.addFontFromFile(@ptrCast(fileName), fontSize);
        zgui.io.setDefaultFont(font);
        c.rlImGuiReloadFonts();
    }

    pub fn deinit(self: *ZXGZguiApp) void {
        rl.closeWindow();
        c.rlImGuiShutdown();
        zgui.deinitNoContext();
        _ = self.gpa.deinit();
    }

    pub fn run(self: *ZXGZguiApp, comptime layoutFn: anytype, context: anytype) !void {
        try self.alloc();

        while (!rl.windowShouldClose()) {
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);
            //const renderCommands, const renderArena = try layoutFn(self.allocator, context);
            try layoutFn(context);
            rl.endDrawing();
        }
    }
};
