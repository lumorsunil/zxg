const std = @import("std");
const backend = @import("backend").backend;
pub const ZXGApp = switch (backend) {
    .Clay => @import("zxg-clay").ZXGApp,
    .Dvui => @import("zxg-dvui").ZXGDvuiApp,
    .Zgui => @import("zxg-zgui").ZXGZguiApp,
    else => {
        std.log.err("Invalid backend {}", .{backend});
    },
};
