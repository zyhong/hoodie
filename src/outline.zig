// This sorts imports statements and present them nicely at the top level of the
// source files.

const std = @import("std");
const mem = std.mem;
const json = std.json;
const Allocator = mem.Allocator;
const ast = std.zig.ast;
const parse = std.zig.parse;
const warn = std.debug.warn;
const ArrayList = std.ArrayList;
const Dump = @import("json/json.zig").Dump;
const testing = std.testing;
const Declaration = struct {
    label: []const u8,
    typ: Type,
    start: usize,
    end: usize,
    children: ArrayList(*Declaration),

    const List = ArrayList(*Declaration);

    const Type = enum {
        Import,
        Const,
        Struct,
        Field,
        Enum,
        Union,
        Fn,
        Test,

        fn encode(self: Type, a: *Allocator) !json.Value {
            return json.Value{
                .String = switch (self) {
                    .Import => "import",
                    .Const => "const",
                    .Struct => "struct",
                    .Field => "field",
                    .Enum => "enum",
                    .Union => "union",
                    .Fn => "function",
                    .Test => "test",
                    else => return error.UnknownType,
                },
            };
        }

        fn fromString(container_kind: []const u8) ?Type {
            if (mem.eql(u8, container_kind, "struct")) {
                return Declaration.Type.Struct;
            } else if (mem.eql(u8, container_kind, "enum")) {
                return Declaration.Type.Enum;
            } else if (mem.eql(u8, container_kind, "union")) {
                return Declaration.Type.Union;
            } else {
                return null;
            }
        }
    };

    fn encode(self: *Declaration, a: *Allocator) anyerror!json.Value {
        var m = json.ObjectMap.init(a);
        _ = try m.put("label", json.Value{
            .String = self.label,
        });
        _ = try m.put("type", try self.typ.encode(a));
        _ = try m.put("start", json.Value{
            .Integer = @intCast(i64, self.start),
        });
        _ = try m.put("end", json.Value{
            .Integer = @intCast(i64, self.end),
        });
        if (self.children.len > 0) {
            var children_list = std.ArrayList(json.Value).init(a);
            for (self.children.toSlice()) |child| {
                try children_list.append(try child.encode(a));
            }
            _ = try m.put("children", json.Value{ .Array = children_list });
        }
        return json.Value{ .Object = m };
    }
};

pub fn outline(a: *Allocator, src: []const u8, stream: var) anyerror!void {
    var tree = try parse(a, src);
    defer tree.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var ls = Declaration.List.init(&arena.allocator);
    defer ls.deinit();

    // tree.root_node.base.dump(0);
    var it = tree.root_node.decls.iterator(0);
    while (true) {
        var decl = (it.next() orelse break).*;
        try collect(
            tree,
            &ls,
            decl,
        );
    }
    try render(a, &ls, stream);
}

fn collect(
    tree: *ast.Tree,
    ls: *Declaration.List,
    decl: *ast.Node,
) !void {
    const first_token_ndex = decl.firstToken();
    const last_token_index = decl.lastToken();
    const first_token = tree.tokens.at(first_token_ndex);
    const last_token = tree.tokens.at(last_token_index);
    switch (decl.id) {
        ast.Node.Id.VarDecl => {
            const var_decl = @fieldParentPtr(ast.Node.VarDecl, "base", decl);
            const decl_name = tree.tokenSlice(var_decl.name_token);
            if (var_decl.init_node) |init_node| {
                switch (init_node.id) {
                    ast.Node.Id.BuiltinCall => {
                        var builtn_call = @fieldParentPtr(ast.Node.BuiltinCall, "base", init_node);
                        const fn_name = tree.tokenSlice(builtn_call.builtin_token);
                        if (mem.eql(u8, fn_name, "@import")) {
                            var decl_ptr = try ls.allocator.create(Declaration);
                            decl_ptr.* = Declaration{
                                .start = first_token.start,
                                .end = last_token.end,
                                .typ = Declaration.Type.Import,
                                .label = decl_name,
                                .children = Declaration.List.init(ls.allocator),
                            };
                            try ls.append(decl_ptr);
                        }
                    },
                    ast.Node.Id.ContainerDecl => {
                        const container_decl = @fieldParentPtr(ast.Node.ContainerDecl, "base", init_node);
                        const container_kind = tree.tokenSlice(container_decl.kind_token);
                        const typ = Declaration.Type.fromString(container_kind);
                        if (typ) |kind| {
                            var decl_ptr = try ls.allocator.create(Declaration);
                            decl_ptr.* = Declaration{
                                .start = first_token.start,
                                .end = last_token.end,
                                .typ = kind,
                                .label = decl_name,
                                .children = Declaration.List.init(ls.allocator),
                            };
                            var it = container_decl.fields_and_decls.iterator(0);
                            while (true) {
                                var field = (it.next() orelse break).*;
                                const field_first_token_ndex = field.firstToken();
                                const field_last_token_index = field.lastToken();
                                const field_first_token = tree.tokens.at(field_first_token_ndex);
                                const field_last_token = tree.tokens.at(field_last_token_index);
                                switch (field.id) {
                                    .ContainerField => {
                                        const field_decl = @fieldParentPtr(ast.Node.ContainerField, "base", field);
                                        const field_name = tree.tokenSlice(field_decl.name_token);
                                        var field_ptr = try ls.allocator.create(Declaration);
                                        field_ptr.* = Declaration{
                                            .start = field_first_token.start,
                                            .end = field_last_token.end,
                                            .typ = Declaration.Type.Field,
                                            .label = field_name,
                                            .children = Declaration.List.init(ls.allocator),
                                        };
                                        try (&decl_ptr.children).append(field_ptr);
                                    },
                                    else => {},
                                }
                            }
                            try ls.append(decl_ptr);
                        }
                    },
                    else => {
                        var decl_ptr = try ls.allocator.create(Declaration);
                        decl_ptr.* = Declaration{
                            .start = first_token.start,
                            .end = last_token.end,
                            .typ = Declaration.Type.Const,
                            .label = decl_name,
                            .children = Declaration.List.init(ls.allocator),
                        };
                        try ls.append(decl_ptr);
                    },
                }
            }
        },
        ast.Node.Id.TestDecl => {
            const test_decl = @fieldParentPtr(ast.Node.TestDecl, "base", decl);
            const name_decl = @fieldParentPtr(ast.Node.StringLiteral, "base", test_decl.name);
            const test_name = tree.tokenSlice(name_decl.token);
            var decl_ptr = try ls.allocator.create(Declaration);
            decl_ptr.* = Declaration{
                .start = first_token.start,
                .end = last_token.end,
                .typ = Declaration.Type.Test,
                .label = unquote(test_name),
                .children = Declaration.List.init(ls.allocator),
            };
            try ls.append(decl_ptr);
        },
        ast.Node.Id.FnProto => {
            const fn_decl = @fieldParentPtr(ast.Node.FnProto, "base", decl);
            if (fn_decl.name_token) |idx| {
                const fn_name = tree.tokenSlice(idx);
                var decl_ptr = try ls.allocator.create(Declaration);
                decl_ptr.* = Declaration{
                    .start = first_token.start,
                    .end = last_token.end,
                    .typ = Declaration.Type.Fn,
                    .label = fn_name,
                    .children = Declaration.List.init(ls.allocator),
                };
                try ls.append(decl_ptr);
            }
        },
        else => {},
    }
}

fn unquote(s: []const u8) []const u8 {
    if (s.len == 0 or s[0] != '"') {
        return s;
    }
    return s[1 .. s.len - 1];
}

fn render(a: *Allocator, ls: *Declaration.List, stream: var) !void {
    var values = ArrayList(json.Value).init(a);
    defer values.deinit();
    for (ls.toSlice()) |decl| {
        var v = try decl.encode(a);
        try values.append(v);
    }
    var v = json.Value{ .Array = values };
    var dump = &try Dump.init(a);
    defer dump.deinit();
    try dump.dump(v, stream);
}

fn testOutline(
    a: *Allocator,
    buf: *std.Buffer,
    src: []const u8,
    expected: []const u8,
) !void {
    try buf.resize(0);
    var stream = &std.io.BufferOutStream.init(buf).stream;
    try outline(a, src, stream);
    if (!buf.eql(expected)) {
        warn("{}", buf.toSlice());
        return;
    }
    testing.expect(buf.eql(expected));
}

test "outline" {
    var a = std.debug.global_allocator;
    var buf = &try std.Buffer.init(a, "");
    defer buf.deinit();

    try testOutline(a, buf,
        \\ const c=@import("c");
        \\
        \\ const a=@import("a");
    ,
        \\[{"end":22,"label":"c","type":"import","start":1},{"end":46,"label":"a","type":"import","start":25}]
    );
    try testOutline(a, buf,
        \\ const c=@import("c").d;
        \\
        \\ const a=@import("a").b.c;
    ,
        \\[{"end":24,"label":"c","type":"const","start":1},{"end":52,"label":"a","type":"const","start":27}]
    );

    try testOutline(a, buf,
        \\test "outline" {}
        \\test "outline2" {}
    ,
        \\[{"end":17,"label":"outline","type":"test","start":0},{"end":36,"label":"outline2","type":"test","start":18}]
    );
    try testOutline(a, buf,
        \\fn outline()void{}
        \\fn outline2()void{}
    ,
        \\[{"end":18,"label":"outline","type":"function","start":0},{"end":38,"label":"outline2","type":"function","start":19}]
    );
    try testOutline(a, buf,
        \\const StructContainer=struct{
        \\  name: []const u8,
        \\ };
    ,
        \\[{"children":[{"end":53,"label":"name","type":"field","start":0}],"end":53,"label":"StructContainer","type":"struct","start":0}]
    );
    try testOutline(a, buf,
        \\const EnumContainer=enum{
        \\  One,
        \\ };
    ,
        \\[{"children":[{"end":36,"label":"One","type":"field","start":0}],"end":36,"label":"EnumContainer","type":"enum","start":0}]
    );
    try testOutline(a, buf,
        \\const UnionContainer=union{};
    ,
        \\[{"end":29,"label":"UnionContainer","type":"union","start":0}]
    );
    try testOutline(a, buf,
        \\const UnionContainer=union{
        \\ A:usize,
        \\ B:[]const u8,
        \\};
    ,
        \\[{"children":[{"end":55,"label":"A","type":"field","start":0},{"end":55,"label":"B","type":"field","start":0}],"end":55,"label":"UnionContainer","type":"union","start":0}]
    );
}
