// This sorts imports statements and present them nicely at the top level of the
// source files.

const std = @import("std");

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const Token = std.zig.Token;

const ast = std.zig.ast;
const json = std.json;
const mem = std.mem;
const parse = std.zig.parse;
const testing = std.testing;
const warn = std.debug.warn;

pub const Span = struct {
    start: Token,
    end: Token,

    pub fn encode(self: Span, a: *Allocator) !json.Value {
        var m = json.ObjectMap.init(a);
        _ = try m.put("startToken", try encodeToken(self.start, a));
        _ = try m.put("endToken", try encodeToken(self.end, a));
        return json.Value{ .Object = m };
    }

    pub fn encodeToken(self: Token, a: *Allocator) !json.Value {
        var m = json.ObjectMap.init(a);
        _ = try m.put("start", json.Value{
            .Integer = @intCast(i64, self.start),
        });
        _ = try m.put("end", json.Value{
            .Integer = @intCast(i64, self.end),
        });
        return json.Value{ .Object = m };
    }
};

/// Stores information about a symbol in a zig source file. This covers
/// declarations at the top level scope of the source file. Since a source file
/// is just a struct container, this can therefore represent top level members of
/// the main struct container(or file in this case).
pub const Declaration = struct {
    /// The string representation of the declared symbol.This is the identifier
    /// name. For instance
    /// ```
    /// const name="gernest";
    /// ```
    /// Here label will be "name"
    label: []const u8,

    /// descripes the kind of the declarion.
    typ: Type,

    /// The position of the first token for this declaration is.
    start: usize,

    /// The position of the last token for this declaration;
    end: usize,

    /// True when the declaration is exported. This means declaration begins with
    /// keyword pub.
    is_public: bool,

    /// true if the declaration starts with var and false when the declation
    /// starts with const.
    is_mutable: bool,

    /// The actual node in the ast for this declaration.
    node: *ast.Node,

    /// sybmol's documentation.
    zig_doc: ?Span,

    /// For container nodes this is the collection of symbols declared within
    /// the container. Containers can be struct,enum or union.
    children: ArrayList(*Declaration),

    pub const List = ArrayList(*Declaration);

    pub const Iterator = struct {
        at: usize,
        ls: []*Declaration,

        pub fn init(ls: *List) Iterator {
            return Iterator{ .at = 0, .ls = ls.toSlice() };
        }

        pub fn next(self: *Iterator) ?*Declaration {
            if (self.at >= self.ls.len) return null;
            var d = self.ls[self.at];
            self.at += 1;
            return d;
        }

        pub fn peek(self: *Iterator) ?*Declaration {
            if (self.at >= self.ls.len) return null;
            var d = self.ls[self.at];
            return d;
        }
    };

    pub const Type = enum {
        Field,
        Import,
        TopAssign, //like import but just struct assignment
        Const,
        Var,
        Struct,
        Method,
        Enum,
        Union,
        Fn,
        Test,

        fn encode(self: Type, a: *Allocator) !json.Value {
            return json.Value{
                .String = switch (self) {
                    .Import => "import",
                    .TopAssign => "topAssign",
                    .Const => "const",
                    .Var => "var",
                    .Struct => "struct",
                    .Field => "field",
                    .Method => "method",
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

        fn mutable(mut: []const u8) Type {
            if (mem.eql(u8, mut, "const")) {
                return Declaration.Type.Const;
            }
            if (mem.eql(u8, mut, "var")) {
                return Declaration.Type.Var;
            }
            unreachable;
        }
    };

    pub fn less(self: *Declaration, b: *Declaration) bool {
        if (@enumToInt(self.typ) <= @enumToInt(Type.TopAssign)) {
            if (self.typ == b.typ) {
                return mem.compare(u8, self.label, b.label) == .LessThan;
            }
            return @enumToInt(self.typ) < @enumToInt(b.typ);
        }
        return false;
    }

    pub fn lessStruct(self: *Declaration, b: *Declaration) bool {
        if (self.typ == b.typ) {
            return false;
        }
        return @enumToInt(self.typ) < @enumToInt(b.typ);
    }

    pub fn sortList(ls: *const List) void {
        std.sort.sort(*Declaration, ls.toSlice(), less);
    }

    pub fn sortListStruct(ls: *const List) void {
        std.sort.sort(*Declaration, ls.toSlice(), lessStruct);
    }

    fn encode(self: *Declaration, a: *Allocator) anyerror!json.Value {
        var m = json.ObjectMap.init(a);
        _ = try m.put("label", json.Value{
            .String = if (self.label.len == 0) "-" else self.label,
        });
        if (self.typ == .TopAssign) {
            if (self.is_mutable) {
                _ = try m.put("type", json.Value{ .String = "var" });
            } else {
                _ = try m.put("type", json.Value{ .String = "const" });
            }
        } else {
            _ = try m.put("type", try self.typ.encode(a));
        }
        _ = try m.put("start", json.Value{
            .Integer = @intCast(i64, self.start),
        });
        _ = try m.put("end", json.Value{
            .Integer = @intCast(i64, self.end),
        });
        _ = try m.put("isPublic", json.Value{
            .Bool = self.is_public,
        });
        if (self.zig_doc) |doc| {
            _ = try m.put("zigDoc", try doc.encode(a));
        }
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

/// outlineDecls collects top level declarations and returns them as a list. The
/// order is as they appear in source file.
pub fn outlineDecls(a: *Allocator, tree: *ast.Tree) anyerror!Declaration.List {
    var ls = Declaration.List.init(a);
    var it = tree.root_node.decls.iterator(0);
    while (true) {
        var decl = (it.next() orelse break).*;
        try collect(tree, &ls, decl);
    }
    return ls;
}

pub fn outlineFromDeclList(
    a: *Allocator,
    tree: *ast.Tree,
    list: *ast.Node.Root.DeclList,
) anyerror!Declaration.List {
    var ls = Declaration.List.init(a);
    var it = list.iterator(0);
    while (true) {
        var decl = (it.next() orelse break).*;
        try collect(tree, &ls, decl);
    }
    return ls;
}

/// Returns text for a zig docummentation of symbols.
fn getDoc(tree: *ast.Tree, doc: ?*ast.Node.DocComment) ?Span {
    if (doc == null) {
        return null;
    }
    const first = tree.tokens.at(doc.?.firstToken());
    const last = tree.tokens.at(doc.?.lastToken());
    return Span{ .start = first.*, .end = last.* };
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
    // decl.dump(0);
    switch (decl.id) {
        .VarDecl => {
            try collectVarDecl(tree, ls, decl);
        },
        .ContainerField => {
            try collectContainerDecl(tree, ls, decl);
        },
        .TestDecl => {
            const test_decl = @fieldParentPtr(ast.Node.TestDecl, "base", decl);
            const name_decl = @fieldParentPtr(ast.Node.StringLiteral, "base", test_decl.name);
            const test_name = tree.tokenSlice(name_decl.token);
            var decl_ptr = try ls.allocator.create(Declaration);
            decl_ptr.* = Declaration{
                .start = first_token.start,
                .end = last_token.end,
                .typ = Declaration.Type.Test,
                .label = unquote(test_name),
                .node = decl,
                .zig_doc = getDoc(tree, test_decl.doc_comments),
                .is_public = false,
                .is_mutable = false,
                .children = Declaration.List.init(ls.allocator),
            };
            try ls.append(decl_ptr);
        },
        .FnProto => {
            try collectFnProto(tree, ls, decl);
        },
        else => {},
    }
}

fn collectFnProto(
    tree: *ast.Tree,
    ls: *Declaration.List,
    decl: *ast.Node,
) !void {
    const first_token_ndex = decl.firstToken();
    const last_token_index = decl.lastToken();
    const first_token = tree.tokens.at(first_token_ndex);
    const last_token = tree.tokens.at(last_token_index);

    const fn_decl = @fieldParentPtr(ast.Node.FnProto, "base", decl);
    if (fn_decl.name_token) |idx| {
        const fn_name = tree.tokenSlice(idx);
        switch (fn_decl.return_type) {
            .Explicit => |n| {
                switch (n.id) {
                    .Identifier => {
                        // Functions that returns type.
                        //
                        // Lots of generic functions are defined this way, and
                        // the Function name is used to represent the returned
                        // type.
                        //
                        // We outline the body of the return function like any
                        // other container for enum,s structs or unions.
                        const ident = @fieldParentPtr(ast.Node.Identifier, "base", n);
                        const txt = tree.tokenSlice(ident.token);
                        if (mem.eql(u8, txt, "type")) {
                            if (fn_decl.body_node) |body| {
                                const block = @fieldParentPtr(ast.Node.Block, "base", body);
                                if (block.statements.count() > 0) {
                                    const last = block.statements.count() - 1;
                                    var ln = block.statements.at(last).*;
                                    const cf = @fieldParentPtr(ast.Node.ControlFlowExpression, "base", ln);
                                    switch (cf.kind) {
                                        .Return => {
                                            if (cf.rhs) |r| {
                                                if (r.id == .ContainerDecl) {
                                                    const container_decl = @fieldParentPtr(ast.Node.ContainerDecl, "base", r);
                                                    const container_kind = tree.tokenSlice(container_decl.kind_token);
                                                    const typ = Declaration.Type.fromString(container_kind);
                                                    if (typ) |kind| {
                                                        var decl_ptr = try ls.allocator.create(Declaration);
                                                        decl_ptr.* = Declaration{
                                                            .start = first_token.start,
                                                            .end = last_token.end,
                                                            .typ = kind,
                                                            .label = fn_name,
                                                            .node = decl,
                                                            .zig_doc = getDoc(tree, fn_decl.doc_comments),
                                                            .is_public = fn_decl.visib_token != null,
                                                            .is_mutable = false,
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
                                                                        .node = field,
                                                                        .zig_doc = getDoc(tree, field_decl.doc_comments),
                                                                        .is_public = field_decl.visib_token != null,
                                                                        .is_mutable = false,
                                                                        .children = Declaration.List.init(ls.allocator),
                                                                    };
                                                                    try decl_ptr.children.append(field_ptr);
                                                                },
                                                                .FnProto => {
                                                                    const ret_fn_decl = @fieldParentPtr(ast.Node.FnProto, "base", field);
                                                                    if (ret_fn_decl.name_token) |ret_idx| {
                                                                        const ret_fn_name = tree.tokenSlice(ret_idx);
                                                                        var fn_decl_ptr = try ls.allocator.create(Declaration);
                                                                        fn_decl_ptr.* = Declaration{
                                                                            .start = field_first_token.start,
                                                                            .end = field_last_token.end,
                                                                            .typ = Declaration.Type.Fn,
                                                                            .label = ret_fn_name,
                                                                            .node = field,
                                                                            .zig_doc = getDoc(tree, ret_fn_decl.doc_comments),
                                                                            .is_public = ret_fn_decl.visib_token != null,
                                                                            .is_mutable = false,
                                                                            .children = Declaration.List.init(ls.allocator),
                                                                        };
                                                                        try decl_ptr.children.append(fn_decl_ptr);
                                                                    }
                                                                },
                                                                .VarDecl => {
                                                                    const field_decl = @fieldParentPtr(ast.Node.VarDecl, "base", field);
                                                                    const field_name = tree.tokenSlice(field_decl.name_token);
                                                                    const f_mut = tree.tokenSlice(field_decl.mut_token);
                                                                    const f_is_mutable = mem.eql(u8, f_mut, "var");
                                                                    var field_ptr = try ls.allocator.create(Declaration);
                                                                    field_ptr.* = Declaration{
                                                                        .start = field_first_token.start,
                                                                        .end = field_last_token.end,
                                                                        .typ = Declaration.Type.mutable(
                                                                            tree.tokenSlice(field_decl.mut_token),
                                                                        ),
                                                                        .label = field_name,
                                                                        .node = field,
                                                                        .zig_doc = getDoc(tree, field_decl.doc_comments),
                                                                        .is_public = field_decl.visib_token != null,
                                                                        .is_mutable = f_is_mutable,
                                                                        .children = Declaration.List.init(ls.allocator),
                                                                    };
                                                                    try decl_ptr.children.append(field_ptr);
                                                                },
                                                                else => {
                                                                    field.dump(0);
                                                                },
                                                            }
                                                        }
                                                        try ls.append(decl_ptr);
                                                    }
                                                    return;
                                                }
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
        var decl_ptr = try ls.allocator.create(Declaration);
        decl_ptr.* = Declaration{
            .start = first_token.start,
            .end = last_token.end,
            .typ = .Fn,
            .label = fn_name,
            .node = decl,
            .zig_doc = getDoc(tree, fn_decl.doc_comments),
            .is_public = fn_decl.visib_token != null,
            .is_mutable = false,
            .children = Declaration.List.init(ls.allocator),
        };
        try ls.append(decl_ptr);
    }
}
fn collectVarDecl(
    tree: *ast.Tree,
    ls: *Declaration.List,
    decl: *ast.Node,
) !void {
    const first_token_ndex = decl.firstToken();
    const last_token_index = decl.lastToken();
    const first_token = tree.tokens.at(first_token_ndex);
    const last_token = tree.tokens.at(last_token_index);
    const var_decl = @fieldParentPtr(ast.Node.VarDecl, "base", decl);
    const decl_name = tree.tokenSlice(var_decl.name_token);
    const mut = tree.tokenSlice(var_decl.mut_token);
    const is_mutable = mem.eql(u8, mut, "const");
    if (var_decl.init_node) |init_node| {
        switch (init_node.id) {
            .BuiltinCall => {
                var builtn_call = @fieldParentPtr(ast.Node.BuiltinCall, "base", init_node);
                const fn_name = tree.tokenSlice(builtn_call.builtin_token);
                if (mem.eql(u8, fn_name, "@import")) {
                    var decl_ptr = try ls.allocator.create(Declaration);
                    decl_ptr.* = Declaration{
                        .start = first_token.start,
                        .end = last_token.end,
                        .typ = Declaration.Type.Import,
                        .label = decl_name,
                        .node = decl,
                        .zig_doc = getDoc(tree, var_decl.doc_comments),
                        .is_public = var_decl.visib_token != null,
                        .is_mutable = is_mutable,
                        .children = Declaration.List.init(ls.allocator),
                    };
                    try ls.append(decl_ptr);
                } else {
                    var decl_ptr = try ls.allocator.create(Declaration);
                    decl_ptr.* = Declaration{
                        .start = first_token.start,
                        .end = last_token.end,
                        .typ = Declaration.Type.mutable(mut),
                        .label = decl_name,
                        .node = decl,
                        .zig_doc = getDoc(tree, var_decl.doc_comments),
                        .is_public = var_decl.visib_token != null,
                        .is_mutable = is_mutable,
                        .children = Declaration.List.init(ls.allocator),
                    };
                    try ls.append(decl_ptr);
                }
            },
            .ContainerDecl => {
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
                        .node = decl,
                        .zig_doc = getDoc(tree, var_decl.doc_comments),
                        .is_public = var_decl.visib_token != null,
                        .is_mutable = is_mutable,
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
                                    .node = field,
                                    .zig_doc = getDoc(tree, field_decl.doc_comments),
                                    .is_public = field_decl.visib_token != null,
                                    .is_mutable = false,
                                    .children = Declaration.List.init(ls.allocator),
                                };
                                try decl_ptr.children.append(field_ptr);
                            },
                            .FnProto => {
                                const fn_decl = @fieldParentPtr(ast.Node.FnProto, "base", field);
                                if (fn_decl.name_token) |idx| {
                                    const fn_name = tree.tokenSlice(idx);
                                    var fn_decl_ptr = try ls.allocator.create(Declaration);
                                    fn_decl_ptr.* = Declaration{
                                        .start = field_first_token.start,
                                        .end = field_last_token.end,
                                        .typ = Declaration.Type.Fn,
                                        .label = fn_name,
                                        .node = field,
                                        .zig_doc = getDoc(tree, fn_decl.doc_comments),
                                        .is_public = fn_decl.visib_token != null,
                                        .is_mutable = false,
                                        .children = Declaration.List.init(ls.allocator),
                                    };
                                    try decl_ptr.children.append(fn_decl_ptr);
                                }
                            },
                            .VarDecl => {
                                const field_decl = @fieldParentPtr(ast.Node.VarDecl, "base", field);
                                const field_name = tree.tokenSlice(field_decl.name_token);
                                const f_mut = tree.tokenSlice(field_decl.mut_token);
                                const f_is_mutable = mem.eql(u8, f_mut, "var");
                                var field_ptr = try ls.allocator.create(Declaration);
                                field_ptr.* = Declaration{
                                    .start = field_first_token.start,
                                    .end = field_last_token.end,
                                    .typ = Declaration.Type.mutable(
                                        tree.tokenSlice(field_decl.mut_token),
                                    ),
                                    .label = field_name,
                                    .node = field,
                                    .zig_doc = getDoc(tree, field_decl.doc_comments),
                                    .is_public = field_decl.visib_token != null,
                                    .is_mutable = f_is_mutable,
                                    .children = Declaration.List.init(ls.allocator),
                                };
                                try decl_ptr.children.append(field_ptr);
                            },
                            else => {
                                field.dump(0);
                            },
                        }
                    }
                    try ls.append(decl_ptr);
                }
            },
            .InfixOp => {
                const infix_decl = @fieldParentPtr(ast.Node.InfixOp, "base", init_node);
                switch (infix_decl.op) {
                    .Period => {
                        var inner = innerMostInfix(infix_decl.lhs);
                        switch (inner.id) {
                            .BuiltinCall => {
                                var builtn_call = @fieldParentPtr(ast.Node.BuiltinCall, "base", inner);
                                const fn_name = tree.tokenSlice(builtn_call.builtin_token);
                                if (mem.eql(u8, fn_name, "@import")) {
                                    var decl_ptr = try ls.allocator.create(Declaration);
                                    decl_ptr.* = Declaration{
                                        .start = first_token.start,
                                        .end = last_token.end,
                                        .typ = Declaration.Type.Import,
                                        .label = decl_name,
                                        .node = decl,
                                        .zig_doc = getDoc(tree, var_decl.doc_comments),
                                        .is_public = var_decl.visib_token != null,
                                        .is_mutable = is_mutable,
                                        .children = Declaration.List.init(ls.allocator),
                                    };
                                    try ls.append(decl_ptr);
                                } else {
                                    var decl_ptr = try ls.allocator.create(Declaration);
                                    decl_ptr.* = Declaration{
                                        .start = first_token.start,
                                        .end = last_token.end,
                                        .typ = Declaration.Type.mutable(mut),
                                        .label = decl_name,
                                        .node = decl,
                                        .zig_doc = getDoc(tree, var_decl.doc_comments),
                                        .is_public = var_decl.visib_token != null,
                                        .is_mutable = is_mutable,
                                        .children = Declaration.List.init(ls.allocator),
                                    };
                                    try ls.append(decl_ptr);
                                }
                            },
                            .Identifier => {
                                var decl_ptr = try ls.allocator.create(Declaration);
                                decl_ptr.* = Declaration{
                                    .start = first_token.start,
                                    .end = last_token.end,
                                    .typ = .TopAssign,
                                    .label = decl_name,
                                    .node = decl,
                                    .zig_doc = getDoc(tree, var_decl.doc_comments),
                                    .is_public = var_decl.visib_token != null,
                                    .is_mutable = is_mutable,
                                    .children = Declaration.List.init(ls.allocator),
                                };
                                try ls.append(decl_ptr);
                            },
                            else => {
                                var decl_ptr = try ls.allocator.create(Declaration);
                                decl_ptr.* = Declaration{
                                    .start = first_token.start,
                                    .end = last_token.end,
                                    .typ = Declaration.Type.mutable(mut),
                                    .label = decl_name,
                                    .node = decl,
                                    .zig_doc = getDoc(tree, var_decl.doc_comments),
                                    .is_public = var_decl.visib_token != null,
                                    .is_mutable = is_mutable,
                                    .children = Declaration.List.init(ls.allocator),
                                };
                                try ls.append(decl_ptr);
                            },
                        }
                    },
                    else => {
                        var decl_ptr = try ls.allocator.create(Declaration);
                        decl_ptr.* = Declaration{
                            .start = first_token.start,
                            .end = last_token.end,
                            .typ = Declaration.Type.mutable(mut),
                            .label = decl_name,
                            .node = decl,
                            .zig_doc = getDoc(tree, var_decl.doc_comments),
                            .is_public = var_decl.visib_token != null,
                            .is_mutable = is_mutable,
                            .children = Declaration.List.init(ls.allocator),
                        };
                        try ls.append(decl_ptr);
                    },
                }
            },
            else => {
                var decl_ptr = try ls.allocator.create(Declaration);
                decl_ptr.* = Declaration{
                    .start = first_token.start,
                    .end = last_token.end,
                    .typ = Declaration.Type.mutable(mut),
                    .label = decl_name,
                    .node = decl,
                    .zig_doc = getDoc(tree, var_decl.doc_comments),
                    .is_public = var_decl.visib_token != null,
                    .is_mutable = is_mutable,
                    .children = Declaration.List.init(ls.allocator),
                };
                try ls.append(decl_ptr);
            },
        }
    }
}

fn collectContainerDecl(
    tree: *ast.Tree,
    ls: *Declaration.List,
    decl: *ast.Node,
) !void {
    const first_token_ndex = decl.firstToken();
    const last_token_index = decl.lastToken();
    const first_token = tree.tokens.at(first_token_ndex);
    const last_token = tree.tokens.at(last_token_index);

    const var_decl = @fieldParentPtr(ast.Node.ContainerField, "base", decl);
    const decl_name = tree.tokenSlice(var_decl.name_token);
    var decl_ptr = try ls.allocator.create(Declaration);
    decl_ptr.* = Declaration{
        .start = first_token.start,
        .end = last_token.end,
        .typ = .Field,
        .label = decl_name,
        .node = decl,
        .zig_doc = getDoc(tree, var_decl.doc_comments),
        .is_public = var_decl.visib_token != null,
        .is_mutable = false,
        .children = Declaration.List.init(ls.allocator),
    };
    try ls.append(decl_ptr);
}

fn innerMostInfix(node: *ast.Node) *ast.Node {
    switch (node.id) {
        .InfixOp => {
            const infix_decl = @fieldParentPtr(ast.Node.InfixOp, "base", node);
            return innerMostInfix(infix_decl.lhs);
        },
        else => {
            return node;
        },
    }
}

fn unquote(s: []const u8) []const u8 {
    if (s.len == 0 or s[0] != '"') {
        return s;
    }
    return s[1 .. s.len - 1];
}

fn dump(a: *Allocator, ls: *Declaration.List) !void {
    var values = std.ArrayList(json.Value).init(a);
    defer values.deinit();
    for (ls.toSlice()) |decl| {
        var v = try decl.encode(a);
        try values.append(v);
    }
    var v = json.Value{ .Array = values };
    v.dump();
}

fn exec(a: *std.mem.Allocator, src: []const u8) anyerror!void {
    var tree = try parse(a, src);
    defer tree.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var ls = &try outlineDecls(&arena.allocator, tree);
    defer ls.deinit();
    try dump(a, ls);
}

fn testOutline(
    a: *Allocator,
    buf: *std.Buffer,
    src: []const u8,
    expected: []const u8,
) !void {
    try exec(a, src);
}

test "outline" {
    var a = std.debug.global_allocator;
    var buf = &try std.Buffer.init(a, "");
    defer buf.deinit();

    // try testOutline(a, buf,
    //     \\ const c=@import("c");
    //     \\
    //     \\ const a=@import("a");
    // ,
    //     \\[{"end":22,"label":"c","type":"import","start":1},{"end":46,"label":"a","type":"import","start":25}]
    // );
    // try testOutline(a, buf,
    //     \\ const c=@import("c").d;
    //     \\
    //     \\ const a=@import("a").b.c;
    // ,
    //     \\[{"end":24,"label":"c","type":"const","start":1},{"end":52,"label":"a","type":"const","start":27}]
    // );

    // try testOutline(a, buf,
    //     \\test "outline" {}
    //     \\test "outline2" {}
    // ,
    //     \\[{"end":17,"label":"outline","type":"test","start":0},{"end":36,"label":"outline2","type":"test","start":18}]
    // );
    // try testOutline(a, buf,
    //     \\fn outline()void{}
    //     \\fn outline2()void{}
    // ,
    //     \\[{"end":18,"label":"outline","type":"function","start":0},{"end":38,"label":"outline2","type":"function","start":19}]
    // );
    // try testOutline(a, buf,
    //     \\var StructContainer=struct{
    //     \\  name: []const u8,
    //     \\ const max=12;
    //     \\var min=20;
    //     \\ pub fn handle(self: StructContainer)void{}
    //     \\ };
    //     \\ pub const major=0.1;
    //     \\ const minor=0.2;
    // ,
    //     \\[{"children":[{"end":53,"label":"name","type":"field","start":0}],"end":53,"label":"StructContainer","type":"struct","start":0}]
    // );
    // try testOutline(a, buf,
    //     \\const EnumContainer=enum{
    //     \\  One,
    //     \\ };
    // ,
    //     \\[{"children":[{"end":36,"label":"One","type":"field","start":0}],"end":36,"label":"EnumContainer","type":"enum","start":0}]
    // );
    // try testOutline(a, buf,
    //     \\const UnionContainer=union{};
    // ,
    //     \\[{"end":29,"label":"UnionContainer","type":"union","start":0}]
    // );
    try testOutline(a, buf,
        \\fn Generic(comptime T:type)type{
        \\    return struct{
        \\        const Self=@This();
        \\        pub fn say()void{}
        \\    };
        \\}
    ,
        \\[{"children":[{"end":55,"label":"A","type":"field","start":0},{"end":55,"label":"B","type":"field","start":0}],"end":55,"label":"UnionContainer","type":"union","start":0}]
    );
}
