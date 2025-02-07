const std = @import("std");
const xml = @import("zig-xml/mod.zig");
const uuid = @import("uuid");
const InterpolationTokenizer = @import("interpolation-tokenizer.zig").InterpolationTokenizer;
const XmlGenError = @import("xml-gen-error.zig").XmlGenError;
const ZigWriter = @import("zig-writer.zig").ZigWriter;

pub const XmlGenWriterZgui = struct {
    indentation: usize,
    writer: ZigWriter,
    varNameIndex: usize = 0,

    const TAB_WIDTH = 4;

    pub fn init(writer: std.fs.File.Writer) XmlGenWriterZgui {
        return XmlGenWriterZgui{
            .indentation = 0,
            .writer = ZigWriter.init(writer),
        };
    }

    pub fn print(self: *XmlGenWriterZgui, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.print(fmt, args);
    }

    pub fn writeAll(self: *XmlGenWriterZgui, s: []const u8) !void {
        try self.writer.writeAll(s);
    }

    pub fn printRaw(self: *XmlGenWriterZgui, comptime fmt: []const u8, args: anytype) !void {
        var buffer: [1024 * 4]u8 = undefined;
        const result = try std.fmt.bufPrint(&buffer, fmt, args);
        var it = std.mem.splitScalar(u8, result, '\n');
        while (it.next()) |p| {
            const trimmed = std.mem.trim(u8, p, " \n\t");
            if (trimmed.len > 0) {
                try self.print("{s}\n", .{trimmed});
            }
        }
    }

    pub fn writeHeader(self: *XmlGenWriterZgui) !void {
        try self.writer.simpleImport("std", "std");
        try self.writer.simpleConst("Allocator", "std.mem.Allocator");
        try self.writer.simpleImport("dvui", "dvui");
        //try self.xmlGenPrintConverterUtilStruct();
    }

    fn xmlGenPrintConverterUtilStruct(self: *XmlGenWriterZgui) !void {
        try self.writeAll(@embedFile("./converter.zig"));
    }

    //fn dvui_frame_basic() !void {
    //    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    //    try tl.addText("Hello, world.", .{});
    //    tl.deinit();
    //}

    pub fn writeUnusedGuard(self: *XmlGenWriterZgui, name: []const u8) !void {
        const handle = self.newHandle();
        const varName = try self.makeVarName("unusedGuard", handle);
        try self.writer.beginConst(varName, .{});
        try self.writer.printInline(".{{ {s} }}", .{name});
        try self.writer.endConst();
        try self.print("_ = {s};\n", .{varName});
    }

    pub fn writeStartLayoutFunction(self: *XmlGenWriterZgui, name: []const u8) !void {
        try self.writer.beginFunction(
            name,
            .{ .isPublic = true },
            &.{.{ .name = "context", .parameterType = "anytype" }},
            "!void",
        );
        try self.writeUnusedGuard("context");
    }

    pub fn writeEndLayoutFunction(self: *XmlGenWriterZgui) !void {
        try self.writer.endFunction();
    }

    pub fn newHandle(self: *XmlGenWriterZgui) usize {
        const handle = self.varNameIndex;
        self.varNameIndex += 1;
        return handle;
    }

    pub inline fn makeVarName(
        self: *XmlGenWriterZgui,
        comptime prefix: []const u8,
        handle: usize,
    ) ![]const u8 {
        _ = self; // autofix
        var varNameBuffer: [16]u8 = undefined;
        return try std.fmt.bufPrint(&varNameBuffer, prefix ++ "_{d}", .{handle});
    }

    pub fn writeText(self: *XmlGenWriterZgui, value: []const u8) !void {
        self.writeStartText();
        self.writeTextValue(value);
        self.writeEndText();
    }

    pub fn writeStartText(self: *XmlGenWriterZgui) !usize {
        const handle = self.newHandle();
        try self.writer.beginBlock(.{});
        const tlVarName = try self.makeVarName("tl", handle);
        try self.writer.beginConst(tlVarName, .{});
        try self.writer.writeTry();
        try self.writer.writeFunctionCall("dvui.textLayout", "@src(), .{}, .{}");
        try self.writer.endConst();
        try self.writer.deinitCall(tlVarName, "", .{ .isDefer = true });
        const textVarName = try self.makeVarName("text", handle);
        try self.writer.beginConst(textVarName, .{});
        return handle;
    }

    pub fn writeTextValue(self: *XmlGenWriterZgui, value: []const u8) !void {
        try self.writer.writeAllInline(value);
    }

    pub fn writeEndText(self: *XmlGenWriterZgui, handle: usize) !void {
        try self.writer.endConst();
        const tlVarName = try self.makeVarName("tl", handle);
        const textVarName = try self.makeVarName("text", handle);
        try self.writer.beginStatement(.{ .isTry = true });
        try self.writer.writeAllInline(tlVarName);
        var argsBuffer: [256]u8 = undefined;
        const args = try std.fmt.bufPrint(&argsBuffer, "{s}, .{{}}", .{textVarName});
        try self.writer.writeFunctionCall(".addText", args);
        try self.writer.endStatement(.FunctionCall);
        try self.writer.endBlock(.{});
    }

    pub fn writeBeginBox(self: *XmlGenWriterZgui, direction: []const u8, options: []const u8) !void {
        const handle = self.newHandle();
        const boxVarName = try self.makeVarName("box", handle);
        try self.writer.beginBlock(.{});
        try self.writer.beginConst(boxVarName, .{});
        try self.writer.writeTry();
        var argsBuffer: [256]u8 = undefined;
        const args = try std.fmt.bufPrint(&argsBuffer, "@src(), {s}, {s}", .{ direction, options });
        try self.writer.writeFunctionCall("dvui.box", args);
        try self.writer.endConst();
        try self.writer.deinitCall(boxVarName, "", .{ .isDefer = true });
    }

    pub fn writeEndBox(self: *XmlGenWriterZgui) !void {
        try self.writer.endBlock(.{});
    }

    pub fn writeValue(self: *XmlGenWriterZgui, comptime T: type, value: []const u8) !void {
        var tokenizer = InterpolationTokenizer.init(value);

        if (tokenizer.hasInterpolation()) {
            switch (T) {
                []const u8 => {
                    try self.writer.writeAll("try std.fmt.allocPrint(frameArenaAllocator, \"");
                    while (tokenizer.next()) |token| {
                        switch (token) {
                            .text => |text| try self.writer.print("{s}", .{text}),
                            .interpolation => try self.writer.print("{{s}}", .{}),
                        }
                    }
                    try self.writer.writeAll("\", .{ ");
                    tokenizer.reset();
                    while (tokenizer.next()) |token| {
                        switch (token) {
                            .text => {},
                            .interpolation => |interp| try self.writer.print("try Converter.convert([]const u8, frameArenaAllocator, {s}), ", .{interp}),
                        }
                    }
                    try self.writer.writeAll(" })");
                },
                else => try self.writer.print("try Converter.convert(" ++ @typeName(T) ++ ", frameArenaAllocator, {s})", .{value}),
            }
        } else {
            switch (T) {
                []const u8 => try self.writer.printInline("\"{s}\"", .{value}),
                else => try self.writer.printInline("try Converter.convert(" ++ @typeName(T) ++ ", frameArenaAllocator, {s})", .{value}),
            }
        }
    }

    pub fn printId(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const id = node.attr("id") orelse &uuid.urn.serialize(uuid.v4.new());
        try self.print(".id = clay.Id(", .{});
        try self.writeValue([]const u8, id);
        try self.writer.print("),\n", .{});
    }

    pub fn printBeginLayout(self: *XmlGenWriterZgui) !void {
        try self.print(".layout = .{{\n", .{});
    }

    pub fn printEndLayout(self: *XmlGenWriterZgui) !void {
        try self.print("}},\n", .{});
    }

    pub fn printSizing(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const value = node.attr("sizing").?;
        if (std.mem.eql(u8, value, "grow")) {
            try self.print(".sizing = clay.Sizing.grow,\n", .{});
        } else if (std.mem.eql(u8, value, "fit")) {
            try self.print(".sizing = clay.Sizing.fit,\n", .{});
        } else if (std.mem.indexOfScalar(u8, value, ' ') == null) {
            const n = std.fmt.parseFloat(f32, value) catch |err| brk: {
                std.log.err("Error parsing sizing attribute \"{s}\": {}", .{ value, err });
                break :brk 0;
            };
            try self.print(".sizing = clay.Sizing.fixed({d}),\n", .{n});
        } else {
            try self.print(".sizing = .{{ .w = ", .{});
            var it = std.mem.splitScalar(u8, value, ' ');
            try self.printSizingAxis(it.next().?);
            try self.writer.print(", .h = ", .{});
            try self.printSizingAxis(it.next().?);
            try self.writer.print(" }},\n", .{});
        }
    }

    fn printSizingAxis(self: *XmlGenWriterZgui, value: []const u8) !void {
        if (std.mem.eql(u8, value, "grow")) {
            try self.writer.print("clay.SizingAxis.grow", .{});
        } else if (std.mem.eql(u8, value, "fit")) {
            try self.writer.print("clay.SizingAxis.fit", .{});
        } else {
            const n = std.fmt.parseFloat(f32, value) catch |err| brk: {
                std.log.err("Error parsing sizing axis attribute \"{s}\": {}", .{ value, err });
                break :brk 0;
            };
            try self.writer.print("clay.SizingAxis.fixed({d})", .{n});
        }
    }

    pub fn printPadding(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const value = node.attr("padding").?;
        var it = std.mem.splitScalar(u8, value, ' ');
        var x: u16 = 0;
        var y: u16 = 0;
        var numberOfValues: usize = 0;
        while (it.next()) |p| {
            numberOfValues += 1;
            const n = std.fmt.parseInt(u16, p, 10) catch |err| brk: {
                std.log.err("Error parsing padding attribute \"{s}\": {}", .{ value, err });
                break :brk 0;
            };
            if (numberOfValues == 1) {
                x = n;
            } else {
                y = n;
            }
        }
        if (numberOfValues == 1) {
            y = x;
        }
        try self.print(".padding = .{{ .x = {d}, .y = {d} }},\n", .{ x, y });
    }

    pub fn printChildGap(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const value = node.attr("child-gap").?;
        try self.print(".child_gap = {s},\n", .{value});
    }

    pub fn printDirection(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const value = node.attr("direction").?;
        if (std.mem.eql(u8, value, "top-to-bottom")) {
            try self.print(".direction = .top_to_bottom,\n", .{});
        } else {
            try self.print(".direction = .left_to_right,\n", .{});
        }
    }

    pub fn printAlignment(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const value = node.attr("alignment").?;

        if (std.mem.eql(u8, value, "left-top")) {
            try self.print(".alignment = .left_top,\n", .{});
        } else if (std.mem.eql(u8, value, "left-bottom")) {
            try self.print(".alignment = .left_bottom,\n", .{});
        } else if (std.mem.eql(u8, value, "left-center")) {
            try self.print(".alignment = .left_center,\n", .{});
        } else if (std.mem.eql(u8, value, "right-top")) {
            try self.print(".alignment = .right_top,\n", .{});
        } else if (std.mem.eql(u8, value, "right-bottom")) {
            try self.print(".alignment = .right_bottom,\n", .{});
        } else if (std.mem.eql(u8, value, "right-center")) {
            try self.print(".alignment = .right_center,\n", .{});
        } else if (std.mem.eql(u8, value, "center-top")) {
            try self.print(".alignment = .center_top,\n", .{});
        } else if (std.mem.eql(u8, value, "center-bottom")) {
            try self.print(".alignment = .center_bottom,\n", .{});
        } else if (std.mem.eql(u8, value, "center-center")) {
            try self.print(".alignment = .center_center,\n", .{});
        }
    }

    pub fn printBeginRectangle(self: *XmlGenWriterZgui) !void {
        try self.writeAll(".rectangle = .{\n");
    }

    pub fn printEndRectangle(self: *XmlGenWriterZgui) !void {
        try self.writeAll("},\n");
    }

    const ColorFormat = enum {
        RGBA,
        Tuple,
    };

    fn getColorFormat(attr: []const u8) ColorFormat {
        var tokenizer = InterpolationTokenizer.init(attr);
        if (tokenizer.hasInterpolation()) {
            while (tokenizer.next()) |token| {
                switch (token) {
                    .text => |text| {
                        if (std.mem.indexOfScalar(u8, text, ' ') != null) {
                            return .RGBA;
                        }
                    },
                    .interpolation => {},
                }
            }

            return .Tuple;
        } else {
            return .RGBA;
        }
    }

    pub fn printColor(self: *XmlGenWriterZgui, node: xml.Element) !void {
        const value = node.attr("color").?;

        switch (getColorFormat(value)) {
            .RGBA => try self.printColorRGBA(value),
            .Tuple => try self.printColorTuple(value),
        }
    }

    fn printColorRGBA(self: *XmlGenWriterZgui, value: []const u8) !void {
        try self.writeAll(".color = clay.Color.init(");
        var tokenizer = InterpolationTokenizer.init(value);

        if (tokenizer.hasInterpolation()) {
            while (tokenizer.next()) |token| {
                switch (token) {
                    .text => |text| {
                        var it = std.mem.splitScalar(u8, text, ' ');
                        while (it.next()) |p| {
                            if (p.len == 0) continue;
                            try self.writeValue(u8, p);
                            try self.writer.writeAll(", ");
                        }
                    },
                    .interpolation => |interp| {
                        try self.writeValue(u8, interp);
                        try self.writer.writeAll(", ");
                    },
                }
            }
        } else {
            var it = std.mem.splitScalar(u8, value, ' ');
            while (it.next()) |p| {
                try self.writeValue(u8, p);
                try self.writer.writeAll(", ");
            }
        }
        try self.writer.writeAll("),\n");
    }

    fn printColorTuple(self: *XmlGenWriterZgui, value: []const u8) !void {
        try self.writeAll(".color = try Converter.convert(clay.Color, frameArenaAllocator, ");
        var tokenizer = InterpolationTokenizer.init(value);
        var numberOfTokens: usize = 0;

        if (tokenizer.hasInterpolation()) {
            while (tokenizer.next()) |token| {
                numberOfTokens += 1;
                if (numberOfTokens > 1) {
                    return XmlGenError.InvalidColorValue;
                }
                switch (token) {
                    .text => {
                        return XmlGenError.InvalidColorValue;
                    },
                    .interpolation => |interp| {
                        try self.print("{s}, ", .{interp});
                    },
                }
            }
        } else {
            return XmlGenError.InvalidColorValue;
        }
        try self.writer.writeAll("),\n");
    }
};
