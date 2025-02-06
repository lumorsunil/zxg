const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const clay = @import("clay");
const clayRenderer = @import("clay_renderer");

fn intsToDimensions(x: i32, y: i32) clay.Dimensions {
    return .{
        .w = @floatFromInt(x),
        .h = @floatFromInt(y),
    };
}

fn intsToVector(x: i32, y: i32) clay.Vector2 {
    return .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
    };
}

fn getLayoutSize() clay.Dimensions {
    return intsToDimensions(rl.getScreenWidth(), rl.getScreenHeight());
}

fn getMousePos() clay.Vector2 {
    return intsToVector(rl.getMouseX(), rl.getMouseY());
}

pub const ZXGApp = struct {
    gpa: GPA = undefined,
    allocator: Allocator = undefined,
    clayMemory: []u8 = undefined,
    arena: clay.Arena = undefined,

    const GPA = std.heap.GeneralPurposeAllocator(.{ .safety = true });

    pub fn init(width: i32, height: i32, comptime title: []const u8) ZXGApp {
        rl.initWindow(width, height, @ptrCast(title));
        rl.setWindowState(.{ .window_resizable = true });

        return ZXGApp{};
    }

    fn alloc(self: *ZXGApp) !void {
        self.gpa = GPA{};
        self.allocator = self.gpa.allocator();

        self.clayMemory = try self.allocator.alloc(u8, clay.minMemorySize());
        self.arena = clay.Arena.init(self.clayMemory);
        clay.initialize(self.arena, getLayoutSize(), .{});
        clay.setMeasureTextFunction(clayRenderer.measureText);
    }

    pub fn deinit(self: *ZXGApp) void {
        rl.closeWindow();
        self.allocator.free(self.clayMemory);
        _ = self.gpa.deinit();
    }

    pub fn loadFont(self: *ZXGApp, comptime fontPath: []const u8, fontSize: i32) void {
        _ = self; // autofix
        _ = clayRenderer.loadFont(@ptrCast(fontPath), fontSize, null);
    }

    pub fn run(self: *ZXGApp, comptime layoutFn: anytype, context: anytype) !void {
        try self.alloc();

        while (!rl.windowShouldClose()) {
            //rl.pollInputEvents();
            clay.setLayoutDimensions(getLayoutSize());
            clay.setPointerState(getMousePos(), rl.isMouseButtonDown(.mouse_button_left));
            clay.updateScrollContainers(true, rl.getMouseWheelMoveV(), rl.getFrameTime());
            rl.beginDrawing();
            rl.clearBackground(rl.Color.white);
            const renderCommands, const renderArena = try layoutFn(self.allocator, context);
            defer renderArena.deinit();
            clayRenderer.render(renderCommands, self.allocator);
            rl.endDrawing();
        }
    }
};
