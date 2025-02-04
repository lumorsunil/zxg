const std = @import("std");

pub const InterpolationTokenizer = struct {
    source: []const u8,

    index: usize,

    const interpolationStart = "${";
    const interpolationEnd = "}";

    pub const Token = union(enum) {
        text: []const u8,
        interpolation: []const u8,
    };

    pub fn init(source: []const u8) InterpolationTokenizer {
        return InterpolationTokenizer{
            .source = source,
            .index = 0,
        };
    }

    pub fn next(self: *InterpolationTokenizer) ?Token {
        if (self.source.len - self.index <= 0) return null;

        if (self.peekSequence("${")) {
            self.index += 2;
            const token = Token{
                .interpolation = self.readUntil(interpolationEnd),
            };
            self.index += 1;
            return token;
        } else {
            return Token{
                .text = self.readUntil(interpolationStart),
            };
        }
    }

    pub fn reset(self: *InterpolationTokenizer) void {
        self.index = 0;
    }

    pub fn hasInterpolation(self: InterpolationTokenizer) bool {
        return std.mem.indexOf(u8, self.source, interpolationStart) != null;
    }

    fn peekSequence(self: InterpolationTokenizer, comptime sequence: []const u8) bool {
        if (self.source.len - self.index < sequence.len) return false;

        inline for (0..sequence.len) |i| {
            if (self.source[self.index + i] != sequence[i]) return false;
        }

        return true;
    }

    fn readUntil(self: *InterpolationTokenizer, sequence: []const u8) []const u8 {
        const endIndex = std.mem.indexOf(u8, self.source[self.index..], sequence);

        if (endIndex) |i| {
            const end = self.index + i;
            const result = self.source[self.index..end];
            self.index = end;
            return result;
        } else {
            const result = self.source[self.index..];
            self.index = self.source.len;
            return result;
        }
    }
};
