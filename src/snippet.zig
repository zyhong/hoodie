const std = @import("std");
const strings = @import("strings/strings.zig");
const warn = std.debug.warn;

pub const Builder = struct {
    buf: *std.Buffer,
    replacer: strings.Replacer,
    choice_replacer: strings.Replacer,
    a: *std.mem.Allocator,
    current_tab_stop: usize,

    pub fn init(a: *std.mem.Allocator, buf: *std.Buffer) !Builder {
        var b = Builder{
            .buf = buf,
            .replacer = strings.Replacer.init(a),
            .choice_replacer = strings.Replacer.init(a),
            .a = a,
            .current_tab_stop = 0,
        };
        try (&b.replacer).add([]const u8{0x5c}, []const u8{ 0x5c, 0x5c });
        try (&b.replacer).add([]const u8{0x7d}, []const u8{ 0x5c, 0x7d });
        try (&b.replacer).add([]const u8{0x24}, []const u8{ 0x5c, 0x24 });

        try (&b.choice_replacer).add([]const u8{0x5c}, []const u8{ 0x5c, 0x5c });
        try (&b.choice_replacer).add([]const u8{0x7d}, []const u8{ 0x5c, 0x7d });
        try (&b.choice_replacer).add([]const u8{0x24}, []const u8{ 0x5c, 0x24 });
        try (&b.choice_replacer).add([]const u8{0x7c}, []const u8{ 0x5c, 0x7c });
        try (&b.choice_replacer).add([]const u8{0x2c}, []const u8{ 0x5c, 0x2c });
        return b;
    }

    pub fn writeChoice(self: *Builder, choices: [][]const u8) !void {
        var stream = &std.io.BufferOutStream.init(&self.buf).stream;
        try stream.write("${");
        try stream.print("{}|", self.nextTabStop());
        var tmp = &try std.Buffer.init(self.a, "");
        defer tmp.deinit();
        for (choices) |choice, i| {
            if (i == 0) {
                try stream.writeByte(',');
            }
            try tmp.resize(0);
            try self.choice_replacer.replace(choice, tmp);
            try stream.write(tmp.toSlice());
        }
        try stream.write("|}");
    }

    fn nextTabStop(self: *Builder) usize {
        self.current_tab_stop += 1;
        return self.current_tab_stop;
    }

    fn writeText(self: *Builder, text: []const u8) !void {
        var tmp = &try std.Buffer.init(self.a, "");
        defer tmp.deinit();
        try self.replacer.replace(text, tmp);
        try self.buf.append(tmp.toSlice());
    }

    fn reset(self: *Builder) !void {
        try self.buf.resize(0);
    }

    fn writePlaceholder(self: *Builder, cb: ?fn (*Builder) !void) !void {
        var stream = &std.io.BufferOutStream.init(&self.buf).stream;
        try stream.write("${");
        try stream.print("{}", self.nextTabStop());
        if (self.cb) |f| {
            try stream.writeByte(':');
            try cb(self);
        }
        try stream.writeByte('}');
    }

    pub fn toSliceConst(self: *Builder) []const u8 {
        return self.toSliceConst();
    }
};

test "Builder" {
    const fixture = struct {
        b: *Builder,
        const Self = @This();
        fn expect(self: *Self, expected: []const u8, cb: fn (*Builder) anyerror!void) !void {
            try self.b.reset();
            try cb(self.b);
            if (self.b.buf.eql(expected)) {
                warn("expected {} got {}\n", expected, self.b.toSliceConst());
            }
        }

        fn case0(self: *Builder) anyerror!void {}
        fn case1(self: *Builder) anyerror!void {
            try self.writeText(
                \\hi { } $ | " , / \
            );
        }
    };
    var a = std.debug.global_allocator;
    var buf = &try std.Buffer.init(a, "");
    defer buf.deinit();

    var b = &try Builder.init(a, buf);
    var ts = &fixture{ .b = b };

    try ts.expect("", fixture.case0);
    try ts.expect(
        \\hi { \} \$ | " , / \\
    ,
        fixture.case1,
    );
}
