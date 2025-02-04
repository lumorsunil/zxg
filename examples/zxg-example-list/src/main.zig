const std = @import("std");
const Allocator = std.mem.Allocator;
const generated = @import("generated-layout");
const ZXGApp = @import("zxg").ZXGApp;

const Context = struct {
    allocator: Allocator,
    items: std.ArrayList(Item),

    pub fn init(allocator: Allocator) !Context {
        return Context{
            .allocator = allocator,
            .items = std.ArrayList(Item).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.items.deinit();
    }

    pub fn getItems(self: *Context) []Item {
        return self.items.items;
    }

    pub fn addItem(self: *Context, label: []const u8) !void {
        try self.items.append(.{ .label = label });
    }

    pub const Item = struct {
        label: []const u8,
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = ZXGApp.init(1024, 800, "Clay UI XML Test");
    defer app.deinit();
    app.loadFont("C:/Windows/Fonts/calibri.ttf", 24);
    var context = try Context.init(allocator);
    defer context.deinit();
    try app.run(generated.layout, &context);
}
