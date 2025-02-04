const std = @import("std");
const clay = @import("clay");
const xml = @import("zig-xml/mod.zig");

pub fn XmlLayout(fileName: []const u8) type {
    const contents = @embedFile(fileName);
    _ = contents; // autofix

    return struct {
        //xml: xml.Document,

        const Self = @This();

        pub fn init() Self {
            return Self{};
        }

        pub fn renderCommands(self: Self) clay.RenderCommandArray {
            _ = self; // autofix
            clay.beginLayout();
            return clay.endLayout();
        }
    };
}
