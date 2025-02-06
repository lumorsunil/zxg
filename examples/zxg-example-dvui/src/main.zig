const std = @import("std");
const zxg = @import("zxg");
const layout = @import("generated-layout").layout;

pub fn main() !void {
    var app = zxg.ZXGApp.init(.{
        .width = 1024,
        .height = 800,
        .title = "ZXG Example - Dvui",
    });
    defer app.deinit();
    try app.run(layout);
}
