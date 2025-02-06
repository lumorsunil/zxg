const std = @import("std");
const Writer = std.fs.File.Writer;

pub const ZigWriter = struct {
    indentation: usize,
    writer: Writer,

    const TAB_WIDTH = 4;

    pub fn init(writer: Writer) ZigWriter {
        return ZigWriter{
            .indentation = 0,
            .writer = writer,
        };
    }

    pub const ZigType = []const u8;

    pub const Parameter = struct {
        name: []const u8,
        parameterType: ZigType,
    };

    pub const DeclarationOptions = struct {
        isPublic: bool = false,
        isComptime: bool = false,
    };

    pub const StatementType = enum {
        FunctionDeclaration,
        Block,
        Assignment,
        FunctionCall,
    };

    pub const StatementOptions = struct {
        isDefer: bool = false,
        isTry: bool = false,
    };

    pub const BlockOptions = struct {
        isComptime: bool = false,
        isInline: bool = false,
    };

    pub fn setIndentation(self: *ZigWriter, indentation: usize) void {
        self.indentation = indentation;
    }

    pub fn incIndentation(self: *ZigWriter) void {
        self.indentation += 1;
    }

    pub fn decIndentation(self: *ZigWriter) void {
        self.indentation -= 1;
    }

    fn writeIndentation(self: *ZigWriter) !void {
        for (0..self.indentation * TAB_WIDTH) |_| {
            try self.writer.print(" ", .{});
        }
    }

    pub fn printInline(self: *ZigWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.print(fmt, args);
    }

    pub fn print(self: *ZigWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.writeIndentation();
        try self.printInline(fmt, args);
    }

    pub fn writeAllInline(self: *ZigWriter, s: []const u8) !void {
        try self.writer.writeAll(s);
    }

    pub fn writeAll(self: *ZigWriter, s: []const u8) !void {
        try self.writeIndentation();
        try self.writeAllInline(s);
    }

    pub fn beginStatement(self: *ZigWriter, options: StatementOptions) !void {
        try self.writeIndentation();
        if (options.isDefer) try self.writeDefer();
        if (options.isTry) try self.writeTry();
    }

    pub fn endStatement(self: *ZigWriter, statementType: StatementType) !void {
        switch (statementType) {
            .FunctionDeclaration, .Block => {},
            .Assignment, .FunctionCall => try self.writeAllInline(";"),
        }

        try self.writeAllInline("\n");
    }

    pub fn beginDeclaration(self: *ZigWriter, options: DeclarationOptions) !void {
        try self.beginStatement(.{});
        if (options.isPublic) {
            try self.writeAllInline("pub ");
        }
        if (options.isComptime) {
            try self.writeAllInline("comptime ");
        }
    }

    pub fn endDeclaration(self: *ZigWriter, statementType: StatementType) !void {
        try self.endStatement(statementType);
    }

    pub fn writeDefer(self: *ZigWriter) !void {
        try self.writeAllInline("defer ");
    }

    pub fn writeTry(self: *ZigWriter) !void {
        try self.writeAllInline("try ");
    }

    pub fn simpleConst(self: *ZigWriter, name: []const u8, value: []const u8) !void {
        try self.beginConst(name, .{});
        try self.writeAllInline(value);
        try self.endConst();
    }

    pub fn beginConst(self: *ZigWriter, name: []const u8, options: DeclarationOptions) !void {
        try self.beginDeclaration(options);
        try self.printInline("const {s} = ", .{name});
    }

    pub fn endConst(self: *ZigWriter) !void {
        try self.endDeclaration(.Assignment);
    }

    pub fn beginBlock(self: *ZigWriter, options: BlockOptions) !void {
        try self.beginStatement(.{});
        try self.writeOpenBlock(options);
    }

    pub fn endBlock(self: *ZigWriter, options: BlockOptions) !void {
        try self.writeCloseBlock(options);
        try self.endStatement(.Block);
    }

    pub fn writeOpenBlock(self: *ZigWriter, options: BlockOptions) !void {
        if (options.isComptime) try self.writeAllInline("comptime ");
        try self.writeAllInline("{");
        if (!options.isInline) {
            try self.writeAllInline("\n");
            self.incIndentation();
        }
    }

    pub fn writeCloseBlock(self: *ZigWriter, options: BlockOptions) !void {
        if (!options.isInline) {
            self.decIndentation();
            try self.writeIndentation();
        }
        try self.writeAllInline("}");
    }

    pub fn beginStruct(self: *ZigWriter) !void {
        try self.writeAllInline("struct {\n");
        self.incIndentation();
    }

    pub fn writeStructField(self: *ZigWriter, name: []const u8, fieldType: ZigType) !void {
        try self.print("{s}: {s},\n", .{ name, fieldType });
    }

    pub fn endStruct(self: *ZigWriter) !void {
        self.decIndentation();
        try self.writeAll("}");
    }

    pub fn beginFunction(
        self: *ZigWriter,
        name: []const u8,
        declarationOptions: DeclarationOptions,
        parameters: []const Parameter,
        returnType: []const u8,
    ) !void {
        try self.beginDeclaration(declarationOptions);
        try self.writeStartFunction(name);
        for (parameters) |parameter| try self.writeParameter(parameter.name, parameter.parameterType);
        try self.writeEndParameters();
        try self.writeReturnType(returnType);
        try self.writeOpenFunctionBody();
    }

    pub fn endFunction(self: *ZigWriter) !void {
        try self.writeCloseFunctionBody();
        try self.endStatement(.FunctionDeclaration);
    }

    pub fn writeStartFunction(self: *ZigWriter, name: []const u8) !void {
        try self.printInline("fn {s}(", .{name});
    }

    pub fn writeParameter(self: *ZigWriter, name: []const u8, parameterType: []const u8) !void {
        try self.printInline("{s}: {s}, ", .{ name, parameterType });
    }

    pub fn writeEndParameters(self: *ZigWriter) !void {
        try self.writeAllInline(") ");
    }

    pub fn writeReturnType(self: *ZigWriter, returnType: []const u8) !void {
        try self.printInline("{s} ", .{returnType});
    }

    pub fn writeOpenFunctionBody(self: *ZigWriter) !void {
        try self.writeOpenBlock(.{});
    }

    pub fn writeCloseFunctionBody(self: *ZigWriter) !void {
        try self.writeCloseBlock(.{});
    }

    pub fn simpleImport(self: *ZigWriter, as: []const u8, module: []const u8) !void {
        try self.beginImport(as, module, .{});
        try self.endImport();
    }

    pub fn beginImport(self: *ZigWriter, as: []const u8, module: []const u8, options: DeclarationOptions) !void {
        try self.beginConst(as, options);
        try self.printInline("@import(\"{s}\")", .{module});
    }

    pub fn endImport(self: *ZigWriter) !void {
        try self.endConst();
    }

    pub fn writeFieldAccessor(self: *ZigWriter, key: []const u8) !void {
        try self.printInline(".{s}", .{key});
    }

    pub fn writeArrayAccessor(self: *ZigWriter, key: []const u8) !void {
        try self.printInline("[{s}]", .{key});
    }

    pub fn assert(self: *ZigWriter, arguments: []const u8) !void {
        try self.functionCall("std.debug.assert", arguments);
    }

    pub fn deinitCall(
        self: *ZigWriter,
        identifier: []const u8,
        arguments: []const u8,
        options: StatementOptions,
    ) !void {
        try self.beginStatement(options);
        try self.writeAllInline(identifier);
        try self.writeFunctionCall(".deinit", arguments);
        try self.endStatement(.FunctionCall);
    }

    pub fn functionCall(
        self: *ZigWriter,
        function: []const u8,
        arguments: []const u8,
        options: StatementOptions,
    ) !void {
        try self.beginStatement(options);
        try self.writeFunctionCall(function, arguments);
        try self.endStatement(.FunctionCall);
    }

    pub fn writeFunctionCall(self: *ZigWriter, function: []const u8, arguments: []const u8) !void {
        try self.printInline("{s}({s})", .{ function, arguments });
    }
};
