const Converter = struct {
    pub const Error = error{CannotConvert};

    fn isString(comptime T: type) bool {
        return comptime switch (@typeInfo(T)) {
            .Array => |array| array.child == u8,
            .Pointer => |pointer| switch (pointer.size) {
                .Many, .Slice => pointer.child == u8,
                else => false,
            },
            else => false,
        };
    }

    fn ConverterFn(comptime To: type) type {
        return (comptime fn (value: anytype) To);
    }

    pub fn convert(comptime To: type, frameArenaAllocator: @import("std").mem.Allocator, value: anytype) !To {
        const From = @TypeOf(value);

        if (From == To) return value;

        switch (@typeInfo(To)) {
            .Float => switch (@typeInfo(From)) {
                .Float => return @floatCast(value),
                .ComptimeFloat => return @floatCast(value),
                .Int => return @floatFromInt(value),
                .ComptimeInt => return @floatFromInt(value),
                else => if (isString(From)) {
                    return @import("std").fmt.parseFloat(To, value);
                } else {
                    return Error.CannotConvert;
                },
            },
            .Int => switch (@typeInfo(From)) {
                .Int => return @intCast(value),
                .ComptimeInt => return @intCast(value),
                .Float => return @intFromFloat(value),
                .ComptimeFloat => return @intFromFloat(value),
                else => if (isString(From)) {
                    return @import("std").fmt.parseInt(To, value, 10);
                } else {
                    return Error.CannotConvert;
                },
            },
            .Struct => if (To == @import("clay").Color) {
                switch (@typeInfo(From)) {
                    .Struct => |struc| {
                        if (struc.is_tuple) {
                            const fields = @import("std").meta.fields(From);
                            if (fields.len == 4) {
                                return @import("clay").Color.init(
                                    value.@"0",
                                    value.@"1",
                                    value.@"2",
                                    value.@"3",
                                );
                            } else {
                                return Error.CannotConvert;
                            }
                        } else {
                            return Error.CannotConvert;
                        }
                    },
                    else => return Error.CannotConvert,
                }
            } else {
                return Error.CannotConvert;
            },
            else => {
                if (isString(To)) {
                    return @import("std").fmt.allocPrint(frameArenaAllocator, "{}", .{@import("std").json.fmt(value, .{})});
                } else {
                    return Error.CannotConvert;
                }
            },
        }
    }
};
