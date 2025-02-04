const std = @import("std");

pub const XmlGenError = error{
    InvalidRootElement,
    InvalidColorValue,
    NotYetImplemented,
} || std.fs.File.WriteError || std.fs.File.OpenError || std.mem.Allocator.Error || error{XmlMalformed};
