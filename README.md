# zxg

An XML-based GUI framework for [Zig](https://ziglang.org/).

This is currently in experimental phase and is not intended for anyone else than myself to use right now.

The backend uses [Clay](https://github.com/nicbarker/clay) and [Raylib](https://github.com/raysan5/raylib) however I might make it backend-agnostic in the future.

zxg also uses [zig-xml](https://github.com/nektro/zig-xml) for parsing the XML.

## Basic Example

### Screenshot

![Basic Example](https://github.com/lumorsunil/zxg/blob/main/docs/images/zxg-example-basic.png)

### Code

You define the GUI with XML mixed with Zig expressions in [layout.xml](https://github.com/lumorsunil/zxg/blob/main/examples/zxg-example-basic/layout.xml):

```xml
<zxg>
    <body>
        <container sizing="grow" direction="top-to-bottom" alignment="center-center">
            <container sizing="grow" alignment="center-center" color="205 175 125 255">
                <text font-size="48">Hello, world!</text>
            </container>
            <container sizing="grow" alignment="top-left" color="150 150 200 255">
                <text font-size="48">Context: ${context.greeting}</text>
            </container>
        </container>
    </body>
</zxg>
```

And here is the corresponding example [main.zig](https://github.com/lumorsunil/zxg/blob/main/examples/zxg-example-basic/src/main.zig):

```zig
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

```

And here is the corresponding example [build.zig](https://github.com/lumorsunil/zxg/blob/main/examples/zxg-example-basic/build.zig):

```zig
const zxg = @import("zxg");

fn build(b: *std.Build) void {

    ...

    const zxgDep = b.dependency("zxg", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zxg", zxgDep.module("zxg"));

    zxg.setup(zxgDep.builder, b, exe, .{
        .target = target,
        .optimize = optimize,
        .layoutPath = "layout.xml",
        .generatedLayoutImport = "generated-layout",
    });

    ...

}
```
