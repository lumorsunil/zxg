const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");

comptime {
    std.debug.assert(dvui.backend_kind == .raylib);
}
const RaylibBackend = dvui.backend;

const vsync = true;
var scale_val: f32 = 1.0;

pub const c = RaylibBackend.c;

pub const ZXGDvuiApp = struct {
    options: InitOptions,

    gpa: GPA = undefined,
    allocator: Allocator = undefined,
    backend: RaylibBackend = undefined,

    const GPA = std.heap.GeneralPurposeAllocator(.{ .safety = true });

    pub const InitOptions = struct {
        width: f32,
        height: f32,
        title: []const u8,
        icon: ?[]const u8 = null,
        logEvents: bool = false,
    };

    pub fn init(
        options: InitOptions,
    ) ZXGDvuiApp {
        return ZXGDvuiApp{
            .options = options,
        };
    }

    pub fn deinit(self: *ZXGDvuiApp) void {
        // init Raylib backend (creates OS window)
        // initWindow() means the backend calls CloseWindow for you in deinit()
        self.backend.deinit();
        _ = self.gpa.deinit();
    }

    fn alloc(self: *ZXGDvuiApp) !void {
        self.gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
        self.allocator = self.gpa.allocator();
        self.backend = try RaylibBackend.initWindow(.{
            .gpa = self.allocator,
            .size = .{ .w = self.options.width, .h = self.options.height },
            .vsync = vsync,
            .title = @ptrCast(self.options.title),
        });
    }

    pub fn run(
        self: *ZXGDvuiApp,
        comptime layout: anytype,
        //context: anytype,
    ) !void {
        try self.alloc();

        self.backend.log_events = self.options.logEvents;

        // init dvui Window (maps onto a single OS window)
        var win = try dvui.Window.init(@src(), self.allocator, self.backend.backend(), .{});
        defer win.deinit();

        main_loop: while (true) {
            c.BeginDrawing();

            // Raylib does not support waiting with event interruption, so dvui
            // can't do variable framerate.  So can't call win.beginWait() or
            // win.waitTime().
            try win.begin(std.time.nanoTimestamp());

            // send all events to dvui for processing
            const quit = try self.backend.addAllEvents(&win);
            if (quit) break :main_loop;

            // if dvui widgets might not cover the whole window, then need to clear
            // the previous frame's render
            self.backend.clear();

            try layout();

            // marks end of dvui frame, don't call dvui functions after this
            // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
            _ = try win.end(.{});

            // cursor management
            self.backend.setCursor(win.cursorRequested());

            // render frame to OS
            c.EndDrawing();
        }
    }
};

fn dvui_frame_basic() !void {
    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    try tl.addText("Hello, world.", .{});
    tl.deinit();
}

fn dvui_frame() !void {
    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(dvui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();

            if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(dvui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui in a normal application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    try tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- example menu at the top of the window
        \\- rest of the window is a scroll area
    , .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is set by Raylib.", .{});
    try tl2.addText("\n\n", .{});
    if (vsync) {
        try tl2.addText("Framerate is capped by vsync.", .{});
    } else {
        try tl2.addText("Framerate is uncapped.", .{});
    }
    try tl2.addText("\n\n", .{});
    try tl2.addText("Cursor is always being set by dvui.", .{});
    try tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        try tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        try tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (try dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    {
        var scaler = try dvui.scale(@src(), scale_val, .{ .expand = .horizontal });
        defer scaler.deinit();

        {
            var hbox = try dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (try dvui.button(@src(), "Zoom In", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
            }

            if (try dvui.button(@src(), "Zoom Out", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
            }
        }

        try dvui.labelNoFmt(@src(), "Below is drawn directly by the backend, not going through DVUI.", .{ .margin = .{ .x = 4 } });

        var box = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 }, .background = true, .margin = .{ .x = 8, .w = 8 } });
        defer box.deinit();

        // Here is some arbitrary drawing that doesn't have to go through DVUI.
        // It can be interleaved with DVUI drawing.
        // NOTE: This only works in the main window (not floating subwindows
        // like dialogs).

        // get the screen rectangle for the box
        const rs = box.data().contentRectScale();

        // rs.r is the pixel rectangle, rs.s is the scale factor (like for
        // hidpi screens or display scaling)
        // raylib multiplies everything internally by the monitor scale, so we
        // have to divide by that
        const r = RaylibBackend.dvuiRectToRaylib(rs.r);
        const s = rs.s / dvui.windowNaturalScale();
        c.DrawText("Congrats! You created your first window!", @intFromFloat(r.x + 10 * s), @intFromFloat(r.y + 10 * s), @intFromFloat(20 * s), c.LIGHTGRAY);
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}
