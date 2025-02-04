const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("codegen-utils.zig");
const XmlGenParser = @import("xml-gen-parser.zig").XmlGenParser;

const MAX_FILE_SIZE = 1024 * 1024 * 4;

fn codegen(allocator: Allocator, inputFilePath: []const u8, writer: std.fs.File.Writer) !void {
    var parser = XmlGenParser.init(allocator, inputFilePath, writer);
    try parser.xmlGen();
}

pub fn main() !void {
    try utils.codegenGeneric(codegen);
}
