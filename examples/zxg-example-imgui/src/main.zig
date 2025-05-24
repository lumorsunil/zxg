const std = @import("std");
const ZXGApp = @import("zxg").ZXGApp;
const Context = struct {
    greeting: []const u8 = "Greetings from context!",
};

fn layout(_: *Context) !void {}

pub fn main() !void {
    var context = Context{};
    var app = ZXGApp.init(1024, 800, "ZXG Example - Basic");
    defer app.deinit();
    try app.loadFont("C:/Windows/Fonts/calibri.ttf", 48);
    try app.run(layout, &context);
}
