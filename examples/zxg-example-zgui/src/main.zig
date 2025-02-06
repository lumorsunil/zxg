const std = @import("std");
const zxg = @import("zxg");
const layout = @import("generated-layout").layout;

pub fn main() !void {
    var app = zxg.ZXGApp.init(1024, 800, "zxg zgui example");
    defer app.deinit();
    try app.loadFont("C:/Windows/Fonts/calibri.ttf", 20);
    try app.run(layout, &.{});
}
