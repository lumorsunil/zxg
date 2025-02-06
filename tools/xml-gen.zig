const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("codegen-utils.zig");
const XmlGenParser = @import("xml-gen-parser.zig").XmlGenParser;
const XmlGenParserDvui = @import("xml-gen-parser-dvui.zig").XmlGenParserDvui;
const XmlGenParserZgui = @import("xml-gen-parser-zgui.zig").XmlGenParserZgui;
const backend = @import("backend").backend;

const isDebug: bool = true;

const MAX_FILE_SIZE = 1024 * 1024 * 4;

fn codegen(allocator: Allocator, inputFilePath: []const u8, writer: std.fs.File.Writer) !void {
    std.log.debug("Generating layout for the {} backend.", .{backend});
    switch (backend) {
        .Clay => {
            var parser = XmlGenParser.init(allocator, inputFilePath, writer);
            try parser.xmlGen();
        },
        .Dvui => {
            var parser = XmlGenParserDvui.init(allocator, inputFilePath, writer);
            try parser.xmlGen();
        },
        .Zgui => {
            var parser = XmlGenParserZgui.init(allocator, inputFilePath, writer);
            try parser.xmlGen();
        },
        .NotSpecified => {
            return error{NoBackendSpecified}.NoBackendSpecified;
        },
    }
}

pub fn main() !void {
    try utils.codegenGeneric(codegen);
}
