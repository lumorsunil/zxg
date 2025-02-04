const std = @import("std");
const Allocator = std.mem.Allocator;
const uuid = @import("uuid");
const xml = @import("zig-xml/mod.zig");
const XmlGenError = @import("xml-gen-error.zig").XmlGenError;
const XmlGenWriter = @import("xml-gen-writer.zig").XmlGenWriter;

pub const XmlGenParser = struct {
    allocator: Allocator,
    fileName: []const u8,
    writer: std.fs.File.Writer,
    xmlWriter: XmlGenWriter,
    documents: std.StringHashMap(xml.Document),
    documentStack: std.ArrayList(*xml.Document),

    pub fn init(allocator: Allocator, fileName: []const u8, writer: std.fs.File.Writer) XmlGenParser {
        return XmlGenParser{
            .allocator = allocator,
            .fileName = fileName,
            .writer = writer,
            .xmlWriter = XmlGenWriter.init(writer),
            .documents = std.StringHashMap(xml.Document).init(allocator),
            .documentStack = std.ArrayList(*xml.Document).init(allocator),
        };
    }

    pub fn deinit(self: *XmlGenParser) void {
        var it = self.documents.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
    }

    fn addDocument(self: *XmlGenParser, fileName: []const u8) !*xml.Document {
        if (self.documents.contains(fileName)) {
            return self.documents.getPtr(fileName).?;
        } else {
            try self.documents.put(fileName, try self.readXml(fileName));
            return self.documents.getPtr(fileName).?;
        }
    }

    fn readXml(self: *XmlGenParser, fileName: []const u8) !xml.Document {
        const file = try std.fs.cwd().openFile(fileName, .{});
        defer file.close();
        return try xml.parse(self.allocator, fileName, file.reader());
    }

    fn pushDocument(self: *XmlGenParser, fileName: []const u8) !*xml.Document {
        const currentDocument = self.documentStack.getLastOrNull();
        if (currentDocument) |cd| cd.release();
        const document = try self.addDocument(fileName);
        document.acquire();
        try self.documentStack.append(document);
        return document;
    }

    fn popDocument(self: *XmlGenParser) !void {
        const topDocument = self.documentStack.pop();
        topDocument.release();
        const nextDocument = self.documentStack.getLast();
        nextDocument.acquire();
    }

    pub fn xmlGen(self: *XmlGenParser) !void {
        const document = try self.pushDocument(self.fileName);

        if (!std.mem.eql(u8, document.root.tag_name.slice(), "zxg")) {
            return XmlGenError.InvalidRootElement;
        }

        try self.xmlWriter.print("// {s}\n\n", .{self.fileName});
        try self.xmlWriter.writeAll("const std = @import(\"std\");\n");
        try self.xmlWriter.writeAll("const Allocator = std.mem.Allocator;\n");
        try self.xmlWriter.writeAll("const clay = @import(\"clay\");\n\n");
        try self.xmlWriter.writeAll("const rl = @import(\"raylib\");\n\n");
        try self.xmlGenPrintConverterUtilStruct();
        try self.xmlGenTagName("head", document.root.children());
        try self.xmlWriter.writeAll("pub fn layout(allocator: Allocator, context: anytype) !std.meta.Tuple(&.{ clay.RenderCommandArray, std.heap.ArenaAllocator }) {\n");
        self.xmlWriter.incIndentation();
        try self.xmlWriter.writeAll("var arena = std.heap.ArenaAllocator.init(allocator);\n");
        //try xmlWriter.writeAll("defer arena.deinit();\n");
        try self.xmlWriter.writeAll("const frameArenaAllocator = arena.allocator();\n");
        try self.xmlWriter.writeAll("const unusedGuard = try frameArenaAllocator.create(u8);\n");
        try self.xmlWriter.writeAll("_ = unusedGuard;\n");
        try self.xmlWriter.writeAll("clay.beginLayout();\n");
        try self.xmlGenTagName("body", document.root.children());
        try self.xmlWriter.writeAll("return .{ clay.endLayout(), arena };\n");
        self.xmlWriter.decIndentation();
        try self.xmlWriter.writeAll("}\n");
    }

    fn xmlGenNodes(self: *XmlGenParser, nodes: []const xml.NodeIndex) anyerror!void {
        for (nodes) |node| try self.xmlGenNode(node);
    }

    fn xmlGenNode(self: *XmlGenParser, node: xml.NodeIndex) anyerror!void {
        switch (node.v()) {
            .element => |element| try self.xmlGenElement(element),
            .text => |text| try self.xmlGenTextRaw(text.slice()),
            .pi => {},
        }
    }

    fn xmlGenElement(self: *XmlGenParser, element: xml.Element) anyerror!void {
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

    fn xmlGenTextRaw(self: *XmlGenParser, text: []const u8) !void {
        try self.xmlGenTextBegin();
        try self.xmlGenTextString(text);
        try self.xmlGenTextEnd(defaultFontSize, defaultTextColor);
    }

    fn xmlGenPrintConverterUtilStruct(self: *XmlGenParser) !void {
        try self.xmlWriter.writeAll(@embedFile("./converter.zig"));
    }

    fn isTagName(node: xml.Element, tagName: []const u8) bool {
        return std.mem.eql(u8, node.tag_name.slice(), tagName);
    }

    fn xmlGenZig(self: *XmlGenParser, node: xml.Element) anyerror!void {
        for (node.children()) |child| {
            switch (child.v()) {
                .text => |text| try self.xmlWriter.printRaw("{s}\n", .{text.slice()}),
                .element => |element| try self.xmlGenElement(element),
                .pi => {},
            }
        }
    }

    fn xmlGenElementWithChildren(self: *XmlGenParser, node: xml.Element) anyerror!void {
        try self.xmlWriter.writeAll("if (clay.open(.{\n");
        try self.xmlGenElementAttributes(node);
        try self.xmlWriter.writeAll("})) {\n");
        self.xmlWriter.incIndentation();
        try self.xmlWriter.writeAll("defer clay.close();\n");
        try self.xmlGenNodes(node.children());
        self.xmlWriter.decIndentation();
        try self.xmlWriter.writeAll("}\n");
    }

    fn xmlGenElementWithoutChildren(self: *XmlGenParser, node: xml.Element) anyerror!void {
        try self.xmlWriter.print("clay.element(.{{\n", .{});
        try self.xmlGenElementAttributes(node);
        try self.xmlWriter.print("}});\n", .{});
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

    fn xmlGenElementAttributes(self: *XmlGenParser, node: xml.Element) anyerror!void {
        self.xmlWriter.incIndentation();
        try self.xmlWriter.printId(node);
        try self.xmlWriter.printBeginLayout();
        if (hasAttr(node, "sizing")) try self.xmlWriter.printSizing(node);
        if (hasAttr(node, "padding")) try self.xmlWriter.printPadding(node);
        if (hasAttr(node, "child-gap")) try self.xmlWriter.printChildGap(node);
        if (hasAttr(node, "direction")) try self.xmlWriter.printDirection(node);
        if (hasAttr(node, "alignment")) try self.xmlWriter.printAlignment(node);
        try self.xmlWriter.printEndLayout();
        if (hasRectangleAttributes(node)) {
            try self.xmlWriter.printBeginRectangle();
            if (hasAttr(node, "color")) try self.xmlWriter.printColor(node);
            try self.xmlWriter.printEndRectangle();
        }
        self.xmlWriter.decIndentation();
    }

    const defaultFontSize = "18";
    const defaultTextColor = "0, 0, 0, 255";

    fn xmlGenVarName() uuid.urn.Urn {
        return uuid.urn.serialize(uuid.v4.new());
    }

    fn xmlGenText(self: *XmlGenParser, node: xml.Element) !void {
        const fontSize = node.attr("font-size") orelse defaultFontSize;
        const textColor = node.attr("text-color") orelse defaultTextColor;
        const text = node.children()[0].v().text.slice();
        const typeAttr = node.attr("type");
        if (typeAttr != null and std.mem.eql(u8, typeAttr.?, "zig")) {
            const varName = xmlGenVarName();
            try self.xmlWriter.print("const @\"text_{s}\" = try std.json.stringifyAlloc(allocator, {s}, .{{}});\n", .{ varName, text });
            try self.xmlWriter.print("defer allocator.free(@\"text_{s}\");\n", .{varName});
            try self.xmlGenTextBegin();
            try self.xmlGenTextVarName(&varName);
        } else {
            try self.xmlGenTextBegin();
            try self.xmlGenTextString(text);
        }
        try self.xmlGenTextEnd(fontSize, textColor);
    }

    fn xmlGenTextBegin(self: *XmlGenParser) !void {
        try self.xmlWriter.print("clay.text(", .{});
    }

    fn xmlGenTextVarName(self: *XmlGenParser, varName: []const u8) !void {
        try self.writer.print("@\"text_{s}\"", .{varName});
    }

    fn xmlGenTextString(self: *XmlGenParser, text: []const u8) !void {
        try self.xmlWriter.printValue([]const u8, text);
    }

    fn xmlGenTextEnd(self: *XmlGenParser, fontSize: []const u8, textColor: []const u8) !void {
        try self.writer.print(
            ", .{{ .font_size = {s}, .text_color = clay.Color.init({s}) }});\n",
            .{ fontSize, textColor },
        );
    }

    fn xmlGenTagName(self: *XmlGenParser, tagName: []const u8, nodes: []const xml.NodeIndex) !void {
        for (nodes) |node| {
            switch (node.v()) {
                .element => |element| if (std.mem.eql(u8, element.tag_name.slice(), tagName)) try self.xmlGenElement(element),
                else => {},
            }
        }
    }

    fn allocImportPath(self: *XmlGenParser, fileName: []const u8) ![]const u8 {
        const importRootDir = "layout";
        return try std.fmt.allocPrint(self.allocator, importRootDir ++ "/{s}", .{fileName});
    }

    fn xmlGenImport(self: *XmlGenParser, element: xml.Element) anyerror!void {
        const fileName = try self.allocImportPath(element.attr("src").?);
        defer self.allocator.free(fileName);
        const extension = std.fs.path.extension(fileName);

        if (std.mem.eql(u8, extension, ".zig")) {
            try self.xmlGenImportZig(fileName);
        } else if (std.mem.eql(u8, extension, ".xml")) {
            try self.xmlGenImportXml(fileName);
        }
    }

    fn xmlGenImportZig(self: *XmlGenParser, fileName: []const u8) !void {
        const zig = try std.fs.cwd().readFileAlloc(self.allocator, fileName, 1024 * 1024 * 8);
        defer self.allocator.free(zig);
        try self.xmlWriter.writeAll(zig);
    }

    fn xmlGenImportXml(self: *XmlGenParser, fileName: []const u8) !void {
        const document = try self.pushDocument(fileName);
        try self.xmlGenNodes(document.root.children());
        try self.popDocument();
    }
};
