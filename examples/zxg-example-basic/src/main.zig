const std = @import("std");

const ZXGApp = @import("zxg").ZXGApp;
const layout = @import("generated-layout").layout;

const Context = struct {
    greeting: []const u8 = "Greetings from context!",
};

pub fn main() !void {
    var app = ZXGApp.init(1024, 800, "ZXG Example - Basic");
    defer app.deinit();
    app.loadFont("C:/Windows/Fonts/calibri.ttf", 48);
    try app.run(layout, &Context{});
}
