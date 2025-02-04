const std = @import("std");
const Allocator = std.mem.Allocator;
const mustache = @import("mustache");
const Variables = @import("variables");
const utils = @import("codegen-utils.zig");

pub fn main() !void {
    try utils.codegenGeneric(mustacheGen);
}

pub fn mustacheGen(allocator: Allocator, inputFilePath: []const u8, writer: std.fs.File.Writer) !void {
    try mustache.renderFile(allocator, inputFilePath, Variables, writer);
}
