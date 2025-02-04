const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn codegenGeneric(
    comptime codegenFn: anytype,
) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    const inputFilePath = args[1];
    const outputFilePath = args[2];
    const outputFile = try std.fs.cwd().createFile(outputFilePath, .{});
    defer outputFile.close();
    const writer = outputFile.writer();
    try codegenFn(allocator, inputFilePath, writer);
    return std.process.cleanExit();
}
