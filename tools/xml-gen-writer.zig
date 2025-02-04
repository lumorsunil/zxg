const std = @import("std");
const xml = @import("zig-xml/mod.zig");
const uuid = @import("uuid");
const InterpolationTokenizer = @import("interpolation-tokenizer.zig").InterpolationTokenizer;
const XmlGenError = @import("xml-gen-error.zig").XmlGenError;

pub const XmlGenWriter = struct {
    indentation: usize,
    writer: std.fs.File.Writer,

    const TAB_WIDTH = 4;

    pub fn init(writer: std.fs.File.Writer) XmlGenWriter {
        return XmlGenWriter{
            .indentation = 0,
            .writer = writer,
        };
    }

    pub fn setIndentation(self: *XmlGenWriter, indentation: usize) void {
        self.indentation = indentation;
    }

    pub fn incIndentation(self: *XmlGenWriter) void {
        self.indentation += 1;
    }

    pub fn decIndentation(self: *XmlGenWriter) void {
        self.indentation -= 1;
    }

    fn printIndentation(self: XmlGenWriter) !void {
        for (0..self.indentation * TAB_WIDTH) |_| {
            try self.writer.print(" ", .{});
        }
    }

    pub fn print(self: XmlGenWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.printIndentation();
        try self.writer.print(fmt, args);
    }

    pub fn writeAll(self: XmlGenWriter, s: []const u8) !void {
        try self.printIndentation();
        try self.writer.writeAll(s);
    }

    pub fn printRaw(self: XmlGenWriter, comptime fmt: []const u8, args: anytype) !void {
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

    pub fn printValue(self: XmlGenWriter, comptime T: type, value: []const u8) !void {
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
                []const u8 => try self.writer.print("\"{s}\"", .{value}),
                else => try self.writer.print("try Converter.convert(" ++ @typeName(T) ++ ", frameArenaAllocator, {s})", .{value}),
            }
        }
    }

    pub fn printId(self: XmlGenWriter, node: xml.Element) !void {
        const id = node.attr("id") orelse &uuid.urn.serialize(uuid.v4.new());
        try self.print(".id = clay.Id(", .{});
        try self.printValue([]const u8, id);
        try self.writer.print("),\n", .{});
    }

    pub fn printBeginLayout(self: *XmlGenWriter) !void {
        try self.print(".layout = .{{\n", .{});
        self.incIndentation();
    }

    pub fn printEndLayout(self: *XmlGenWriter) !void {
        self.decIndentation();
        try self.print("}},\n", .{});
    }

    pub fn printSizing(self: XmlGenWriter, node: xml.Element) !void {
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

    fn printSizingAxis(self: XmlGenWriter, value: []const u8) !void {
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

    pub fn printPadding(self: XmlGenWriter, node: xml.Element) !void {
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

    pub fn printChildGap(self: XmlGenWriter, node: xml.Element) !void {
        const value = node.attr("child-gap").?;
        try self.print(".child_gap = {s},\n", .{value});
    }

    pub fn printDirection(self: XmlGenWriter, node: xml.Element) !void {
        const value = node.attr("direction").?;
        if (std.mem.eql(u8, value, "top-to-bottom")) {
            try self.print(".direction = .top_to_bottom,\n", .{});
        } else {
            try self.print(".direction = .left_to_right,\n", .{});
        }
    }

    pub fn printAlignment(self: XmlGenWriter, node: xml.Element) !void {
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

    pub fn printBeginRectangle(self: *XmlGenWriter) !void {
        try self.writeAll(".rectangle = .{\n");
        self.incIndentation();
    }

    pub fn printEndRectangle(self: *XmlGenWriter) !void {
        self.decIndentation();
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

    pub fn printColor(self: XmlGenWriter, node: xml.Element) !void {
        const value = node.attr("color").?;

        switch (getColorFormat(value)) {
            .RGBA => try self.printColorRGBA(value),
            .Tuple => try self.printColorTuple(value),
        }
    }

    fn printColorRGBA(self: XmlGenWriter, value: []const u8) !void {
        try self.writeAll(".color = clay.Color.init(");
        var tokenizer = InterpolationTokenizer.init(value);

        if (tokenizer.hasInterpolation()) {
            while (tokenizer.next()) |token| {
                switch (token) {
                    .text => |text| {
                        var it = std.mem.splitScalar(u8, text, ' ');
                        while (it.next()) |p| {
                            if (p.len == 0) continue;
                            try self.printValue(u8, p);
                            try self.writer.writeAll(", ");
                        }
                    },
                    .interpolation => |interp| {
                        try self.printValue(u8, interp);
                        try self.writer.writeAll(", ");
                    },
                }
            }
        } else {
            var it = std.mem.splitScalar(u8, value, ' ');
            while (it.next()) |p| {
                try self.printValue(u8, p);
                try self.writer.writeAll(", ");
            }
        }
        try self.writer.writeAll("),\n");
    }

    fn printColorTuple(self: XmlGenWriter, value: []const u8) !void {
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
