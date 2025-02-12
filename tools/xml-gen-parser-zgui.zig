const std = @import("std");
const Allocator = std.mem.Allocator;
const uuid = @import("uuid");
const xml = @import("zig-xml");
const XmlGenError = @import("xml-gen-error.zig").XmlGenError;
const XmlGenWriter = @import("xml-gen-writer-zgui.zig").XmlGenWriterZgui;
const InterpolationTokenizer = @import("interpolation-tokenizer.zig").InterpolationTokenizer;

pub const XmlGenParserZgui = struct {
    allocator: Allocator,
    fileName: []const u8,
    writer: std.fs.File.Writer,
    xmlWriter: XmlGenWriter,
    documents: std.StringHashMap(xml.Document),
    documentStack: std.ArrayList(*xml.Document),

    pub fn init(allocator: Allocator, fileName: []const u8, writer: std.fs.File.Writer) XmlGenParserZgui {
        return XmlGenParserZgui{
            .allocator = allocator,
            .fileName = fileName,
            .writer = writer,
            .xmlWriter = XmlGenWriter.init(writer),
            .documents = std.StringHashMap(xml.Document).init(allocator),
            .documentStack = std.ArrayList(*xml.Document).init(allocator),
        };
    }

    pub fn deinit(self: *XmlGenParserZgui) void {
        var it = self.documents.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
    }

    fn addDocument(self: *XmlGenParserZgui, fileName: []const u8) !*xml.Document {
        if (self.documents.contains(fileName)) {
            return self.documents.getPtr(fileName).?;
        } else {
            try self.documents.put(fileName, try self.readXml(fileName));
            return self.documents.getPtr(fileName).?;
        }
    }

    fn readXml(self: *XmlGenParserZgui, fileName: []const u8) !xml.Document {
        const file = try std.fs.cwd().openFile(fileName, .{});
        defer file.close();
        return try xml.parse(self.allocator, fileName, file.reader());
    }

    fn pushDocument(self: *XmlGenParserZgui, fileName: []const u8) !*xml.Document {
        const currentDocument = self.documentStack.getLastOrNull();
        if (currentDocument) |cd| cd.release();
        const document = try self.addDocument(fileName);
        document.acquire();
        try self.documentStack.append(document);
        return document;
    }

    fn popDocument(self: *XmlGenParserZgui) !void {
        const topDocument = self.documentStack.pop();
        topDocument.release();
        const nextDocument = self.documentStack.getLast();
        nextDocument.acquire();
    }

    pub fn xmlGen(self: *XmlGenParserZgui) !void {
        const document = try self.pushDocument(self.fileName);

        if (!std.mem.eql(u8, document.root.tag_name.slice(), "zxg")) {
            return XmlGenError.InvalidRootElement;
        }

        try self.xmlWriter.print("// {s}\n\n", .{self.fileName});
        try self.xmlWriter.writeHeader();
        try self.xmlGenTagName("head", document.root.children());

        //fn dvui_frame_basic() !void {
        //    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
        //    try tl.addText("Hello, world.", .{});
        //    tl.deinit();
        //}

        try self.xmlWriter.writeStartLayoutFunction("layout");
        try self.xmlGenTagName("body", document.root.children());
        try self.xmlWriter.writeEndLayoutFunction();

        //        try self.xmlWriter.writeAll("pub fn layout(allocator: Allocator, context: anytype) !std.meta.Tuple(&.{ clay.RenderCommandArray, std.heap.ArenaAllocator }) {\n");
        //        self.xmlWriter.incIndentation();
        //        try self.xmlWriter.writeAll("var arena = std.heap.ArenaAllocator.init(allocator);\n");
        //        //try xmlWriter.writeAll("defer arena.deinit();\n");
        //        try self.xmlWriter.writeAll("const frameArenaAllocator = arena.allocator();\n");
        //        try self.xmlWriter.writeAll("const unusedGuard = try frameArenaAllocator.create(u8);\n");
        //        try self.xmlWriter.writeAll("_ = unusedGuard;\n");
        //        try self.xmlWriter.writeAll("clay.beginLayout();\n");
        //        try self.xmlGenTagName("body", document.root.children());
        //        try self.xmlWriter.writeAll("return .{ clay.endLayout(), arena };\n");
        //        self.xmlWriter.decIndentation();
        //        try self.xmlWriter.writeAll("}\n");
    }

    fn xmlGenNodes(self: *XmlGenParserZgui, nodes: []const xml.NodeIndex) anyerror!void {
        for (nodes) |node| try self.xmlGenNode(node);
    }

    fn xmlGenNode(self: *XmlGenParserZgui, node: xml.NodeIndex) anyerror!void {
        switch (node.v()) {
            .element => |element| try self.xmlGenElement(element),
            .text => |text| try self.xmlGenTextRaw(text.slice()),
            .pi => {},
        }
    }

    fn xmlGenElement(self: *XmlGenParserZgui, element: xml.Element) anyerror!void {
        if (isTagName(element, "head")) {
            return self.xmlGenNodes(element.children());
        } else if (isTagName(element, "body")) {
            return self.xmlGenNodes(element.children());
        } else if (isTagName(element, "import")) {
            return self.xmlGenImport(element);
        } else if (isTagName(element, "text")) {
            try self.xmlGenText(element);
        } else if (isTagName(element, "zig")) {
            try self.xmlGenZig(element);
        } else if (element.children().len > 0) {
            try self.xmlGenElementWithChildren(element);
        } else {
            try self.xmlGenElementWithoutChildren(element);
        }
    }

    fn xmlGenTextRaw(self: *XmlGenParserZgui, text: []const u8) !void {
        const handle = try self.xmlWriter.writeStartText();
        try self.xmlGenTextString(text);
        try self.xmlWriter.writeEndText(handle);
    }

    fn isTagName(node: xml.Element, tagName: []const u8) bool {
        return std.mem.eql(u8, node.tag_name.slice(), tagName);
    }

    fn xmlGenZig(self: *XmlGenParserZgui, node: xml.Element) anyerror!void {
        for (node.children()) |child| {
            switch (child.v()) {
                .text => |text| try self.xmlWriter.printRaw("{s}\n", .{text.slice()}),
                .element => |element| try self.xmlGenElement(element),
                .pi => {},
            }
        }
    }

    fn xmlGenElementWithChildren(self: *XmlGenParserZgui, node: xml.Element) anyerror!void {
        if (std.mem.eql(u8, node.tag_name.slice(), "box")) {
            try self.xmlGenBox(node);
        } else {
            return XmlGenError.NotYetImplemented;
        }

        //        try self.xmlWriter.writeAll("if (clay.open(.{\n");
        //        try self.xmlGenElementAttributes(node);
        //        try self.xmlWriter.writeAll("})) {\n");
        //        try self.xmlWriter.writeAll("defer clay.close();\n");
        //        try self.xmlGenNodes(node.children());
        //        try self.xmlWriter.writeAll("}\n");
    }

    fn xmlGenElementWithoutChildren(self: *XmlGenParserZgui, node: xml.Element) anyerror!void {
        try self.xmlWriter.print("clay.element(.{{\n", .{});
        try self.xmlGenElementAttributes(node);
        try self.xmlWriter.print("}});\n", .{});
    }

    pub const Direction = enum {
        horizontal,
        vertical,

        pub fn fromAttr(attr: ?[]const u8) Direction {
            if (attr) |a| if (std.mem.eql(u8, a, "left-to-right")) return .horizontal;
            return .vertical;
        }

        pub fn toDvui(self: Direction) []const u8 {
            return switch (self) {
                .horizontal => ".horizontal",
                .vertical => ".vertical",
            };
        }
    };

    pub const Expand = enum {
        horizontal,
        vertical,
        both,
        none,

        pub const default: Expand = .horizontal;

        pub fn fromAttr(attr: ?[]const u8) Expand {
            if (attr == null) return .horizontal;
            const a = attr.?;
            var tokenizer = InterpolationTokenizer.init(a);
            if (tokenizer.hasInterpolation()) {
                return default;
            } else if (std.mem.indexOfScalar(u8, a, ' ') != null) {
                return fromPartsString(a);
            } else {
                const part = fromPart(a);
                return fromParts(.{ part, part });
            }
        }

        const Part = enum {
            grow,
            fit,
        };

        fn fromPart(part: []const u8) ?Part {
            if (std.mem.eql(u8, part, "grow")) return .grow;
            if (std.mem.eql(u8, part, "fit")) return .fit;
            return null;
        }

        fn fromParts(parts: struct { ?Part, ?Part }) Expand {
            const x, const y = parts;
            if (x == null and y == null) return default;
            if (x == null and y.? == .grow) return .vertical;
            if (x == null and y.? == .fit) return .horizontal;
            if (x.? == .grow and y == null) return .horizontal;
            if (x.? == .fit and y == null) return .vertical;
            if (x.? == .grow and y.? == .grow) return .both;
            if (x.? == .fit and y.? == .grow) return .vertical;
            if (x.? == .grow and y.? == .fit) return .horizontal;
            if (x.? == .fit and y.? == .fit) return .none;
            unreachable;
        }

        fn fromPartsString(attr: []const u8) Expand {
            var it = std.mem.splitScalar(u8, attr, ' ');
            const x = fromPart(it.next().?);
            const y = fromPart(it.next().?);
            return fromParts(.{ x, y });
        }

        pub fn toDvui(self: Expand) []const u8 {
            return switch (self) {
                .horizontal => ".expand = .horizontal, ",
                .vertical => ".expand = .vertical, ",
                .both => ".expand = .both, ",
                .none => "",
            };
        }
    };

    pub const Gravity = struct {
        x: Part,
        y: Part,

        pub const default = Gravity{
            .x = Part.default,
            .y = Part.default,
        };

        pub const Part = enum {
            start,
            end,
            center,

            pub const default: Part = .start;

            pub fn toDvui(self: Part) []const u8 {
                return switch (self) {
                    .start => "0.0",
                    .end => "1.0",
                    .center => "0.5",
                };
            }
        };

        pub fn fromAttr(attr: ?[]const u8) Gravity {
            if (attr == null) return default;

            var it = std.mem.splitScalar(u8, attr.?, '-');
            const x = it.next().?;
            const y = it.next().?;

            return Gravity{
                .x = xFromPart(x),
                .y = yFromPart(y),
            };
        }

        pub fn xFromPart(part: []const u8) Part {
            if (std.mem.eql(u8, part, "left")) return .start;
            if (std.mem.eql(u8, part, "right")) return .end;
            if (std.mem.eql(u8, part, "center")) return .center;
            return Part.default;
        }

        pub fn yFromPart(part: []const u8) Part {
            if (std.mem.eql(u8, part, "top")) return .start;
            if (std.mem.eql(u8, part, "bottom")) return .end;
            if (std.mem.eql(u8, part, "center")) return .center;
            return Part.default;
        }

        pub inline fn toDvui(self: Gravity) ![]const u8 {
            var buffer: [512]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buffer);
            const writer = stream.writer();

            try writer.print(
                ".gravity_x = {s}, .gravity_y = {s}, ",
                .{ self.x.toDvui(), self.y.toDvui() },
            );

            return stream.getWritten();
        }
    };

    pub const ColorOrName = union(enum) {
        name: enum { fill },
        color: struct { r: u8, g: u8, b: u8, a: u8 },

        pub const default: ColorOrName = .{ .name = .fill };

        pub fn fromAttr(maybeAttr: ?[]const u8) !ColorOrName {
            if (maybeAttr == null) return default;
            const attr = maybeAttr.?;

            var tokenizer = InterpolationTokenizer.init(attr);
            if (tokenizer.hasInterpolation()) {
                // TODO: Implement
                return default;
            } else if (std.mem.startsWith(u8, attr, "rgba(")) {
                var it = std.mem.tokenizeAny(u8, attr[5..], " ,()");
                const r = try std.fmt.parseInt(u8, it.next().?, 10);
                const g = try std.fmt.parseInt(u8, it.next().?, 10);
                const b = try std.fmt.parseInt(u8, it.next().?, 10);
                const a = try std.fmt.parseInt(u8, it.next().?, 10);
                return .{ .color = .{ .r = r, .g = g, .b = b, .a = a } };
            } else if (attr[0] == '#') {
                //return .{ .color = try dvui.Color.fromHex(@constCast(attr[0..7]).*) };
                return XmlGenError.NotYetImplemented;
            }
            // TODO: hsl etc

            return default;
        }

        pub inline fn toDvui(self: ColorOrName) ![]const u8 {
            var buffer: [512]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buffer);
            const writer = stream.writer();

            try writer.writeAll(".color_fill = ");
            switch (self) {
                .name => |name| {
                    try writer.print(".{{ .name = .{s} }}", .{@tagName(name)});
                },
                .color => |color| {
                    try writer.print(
                        ".{{ .color = .{{ .r = {d}, .g = {d}, .b = {d}, .a = {d} }} }}",
                        .{ color.r, color.g, color.b, color.a },
                    );
                },
            }
            try writer.writeAll(", .background = true, ");

            return stream.getWritten();
        }
    };

    pub const ElementOptions = struct {
        expand: Expand,
        gravity: Gravity,
        color: ColorOrName,

        pub fn fromElement(element: xml.Element) !ElementOptions {
            return ElementOptions{
                .expand = Expand.fromAttr(element.attr("sizing")),
                .gravity = Gravity.fromAttr(element.attr("alignment")),
                .color = try ColorOrName.fromAttr(element.attr("color")),
            };
        }

        pub inline fn toDvui(self: ElementOptions) ![]const u8 {
            var buffer: [512]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buffer);
            const writer = stream.writer();

            try writer.writeAll(".{ ");
            try writer.writeAll(self.expand.toDvui());
            try writer.writeAll(try self.gravity.toDvui());
            try writer.writeAll(try self.color.toDvui());
            try writer.writeAll("}");

            return stream.getWritten();
        }
    };

    fn xmlGenBox(self: *XmlGenParserZgui, node: xml.Element) !void {
        const direction = Direction.fromAttr(node.attr("direction")).toDvui();
        const options = try (try ElementOptions.fromElement(node)).toDvui();
        try self.xmlWriter.writeBeginBox(direction, options);
        try self.xmlGenNodes(node.children());
        try self.xmlWriter.writeEndBox();
    }

    fn hasAttr(node: xml.Element, attr: []const u8) bool {
        return node.attr(attr) != null;
    }

    fn hasAnyAttr(node: xml.Element, attrs: []const []const u8) bool {
        for (attrs) |attr| if (!hasAttr(node, attr)) return false;
        return true;
    }

    fn hasRectangleAttributes(node: xml.Element) bool {
        return hasAnyAttr(node, &.{"color"});
    }

    fn xmlGenElementAttributes(self: *XmlGenParserZgui, node: xml.Element) anyerror!void {
        //try self.xmlWriter.printId(node);
        try self.xmlWriter.printBeginLayout();
        if (hasAttr(node, "sizing")) try self.xmlWriter.printSizing(node);
        //if (hasAttr(node, "padding")) try self.xmlWriter.printPadding(node);
        //if (hasAttr(node, "child-gap")) try self.xmlWriter.printChildGap(node);
        //if (hasAttr(node, "direction")) try self.xmlWriter.printDirection(node);
        //if (hasAttr(node, "alignment")) try self.xmlWriter.printAlignment(node);
        try self.xmlWriter.printEndLayout();
        //        if (hasRectangleAttributes(node)) {
        //            try self.xmlWriter.printBeginRectangle();
        //            if (hasAttr(node, "color")) try self.xmlWriter.printColor(node);
        //            try self.xmlWriter.printEndRectangle();
        //        }
    }

    const defaultFontSize = "18";
    const defaultTextColor = "0, 0, 0, 255";

    fn xmlGenVarName() uuid.urn.Urn {
        return uuid.urn.serialize(uuid.v4.new());
    }

    fn xmlGenText(self: *XmlGenParserZgui, node: xml.Element) !void {
        //        const fontSize = node.attr("font-size") orelse defaultFontSize;
        //        const textColor = node.attr("text-color") orelse defaultTextColor;
        const text = node.children()[0].v().text.slice();
        const handle = try self.xmlWriter.writeStartText();
        try self.xmlGenTextString(text);
        try self.xmlWriter.writeEndText(handle);
    }

    fn xmlGenTextVarName(self: *XmlGenParserZgui, varName: []const u8) !void {
        try self.writer.print("@\"text_{s}\"", .{varName});
    }

    fn xmlGenTextString(self: *XmlGenParserZgui, text: []const u8) !void {
        try self.xmlWriter.writeValue([]const u8, text);
    }

    fn xmlGenTagName(self: *XmlGenParserZgui, tagName: []const u8, nodes: []const xml.NodeIndex) !void {
        for (nodes) |node| {
            switch (node.v()) {
                .element => |element| if (std.mem.eql(u8, element.tag_name.slice(), tagName)) try self.xmlGenElement(element),
                else => {},
            }
        }
    }

    fn allocImportPath(self: *XmlGenParserZgui, fileName: []const u8) ![]const u8 {
        const importRootDir = "layout";
        return try std.fmt.allocPrint(self.allocator, importRootDir ++ "/{s}", .{fileName});
    }

    fn xmlGenImport(self: *XmlGenParserZgui, element: xml.Element) anyerror!void {
        const fileName = try self.allocImportPath(element.attr("src").?);
        defer self.allocator.free(fileName);
        const extension = std.fs.path.extension(fileName);

        if (std.mem.eql(u8, extension, ".zig")) {
            try self.xmlGenImportZig(fileName);
        } else if (std.mem.eql(u8, extension, ".xml")) {
            try self.xmlGenImportXml(fileName);
        }
    }

    fn xmlGenImportZig(self: *XmlGenParserZgui, fileName: []const u8) !void {
        const zig = try std.fs.cwd().readFileAlloc(self.allocator, fileName, 1024 * 1024 * 8);
        defer self.allocator.free(zig);
        try self.xmlWriter.writeAll(zig);
    }

    fn xmlGenImportXml(self: *XmlGenParserZgui, fileName: []const u8) !void {
        const document = try self.pushDocument(fileName);
        try self.xmlGenNodes(document.root.children());
        try self.popDocument();
    }
};
