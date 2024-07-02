const std = @import("std");
const Self = @This();
const Allocator = std.mem.Allocator;

const State = struct {
    current_component: ?*VNode = null,
    seen_components: std.StringArrayHashMapUnmanaged(usize) = .{},
    current_hook_index: usize = 0,
};

arena: Allocator,
state: State,
// component_map: std.StringArrayHashMapUnmanaged(Component),

pub fn init(arena: Allocator) Self {
    return Self{
        .arena = arena,
        .state = .{},
        // .components = .{},
    };
}

pub const Element = struct {
    class: []const u8,
    text: []const u8,
};
pub const Component = struct {
    pub const Hook = struct {
        ptr: *anyopaque,
    };
    type_name: []const u8,
    parent: ?*VNode,
    // hooks: std.ArrayListUnmanaged(Hook),
};

pub const VNodeType = union(enum) {
    element: Element,
    component: Component,
};

pub const VNode = struct {
    key: []const u8,
    ty: VNodeType,
    //
    parent: ?*VNode = null,
    first_child: ?*VNode = null,
    next_sibling: ?*VNode = null,
};

pub fn createText(self: *Self, text: []const u8) *VNode {
    return self.createElement(.{
        .text = text,
    });
}

const ElementProps = struct {
    key: []const u8 = "",
    text: []const u8 = "",
    class: []const u8 = "",
    children: ?[]const *VNode = null,
};
pub fn createElement(self: *Self, props: ElementProps) *VNode {
    const key = if (props.key.len == 0) "element" else props.key;

    const parent = self.arena.create(VNode) catch unreachable;
    parent.* = VNode{
        .key = key,
        .ty = .{
            .element = Element{
                .class = self.arena.dupe(u8, props.class) catch unreachable,
                .text = self.arena.dupe(u8, props.text) catch unreachable,
            },
        },
    };

    if (props.children) |stack_children| {
        const children = self.arena.alloc(*VNode, stack_children.len) catch unreachable;
        for (0..stack_children.len) |i| {
            children[i] = stack_children[i];
        }

        for (children) |child_ptr| {
            child_ptr.parent = parent;
            if (parent.first_child == null) {
                parent.first_child = child_ptr;
            } else {
                var child = parent.first_child;
                while (child) |item| {
                    if (item.next_sibling == null) {
                        item.next_sibling = child_ptr;
                        break;
                    }
                    child = item.next_sibling;
                }
            }
        }
    }

    return parent;
}

const InstanceProps = struct {
    key: []const u8 = "",
};

/// we go traverse theorugh the parents to build a full key
pub fn generateUniqueId(self: *Self, my_key: []const u8) []const u8 {
    if (self.state.current_component) |current| {
        var key = std.ArrayList(u8).init(self.arena);
        key.appendSlice(current.key) catch unreachable;
        key.append('/') catch unreachable;
        key.appendSlice(my_key) catch unreachable;

        const entry = self.state.seen_components.getOrPut(self.arena, key.items) catch unreachable;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 0;
        }

        key.append('/') catch unreachable;
        key.appendSlice(std.fmt.allocPrint(self.arena, "{d}", .{entry.value_ptr.*}) catch unreachable) catch unreachable;

        return key.items;
    }

    return my_key;
}

pub fn createInstance(self: *Self, comp: anytype, props: InstanceProps) *VNode {
    // const Wrapper = struct {
    //     pub fn render(s: *anyopaque, tree: *Self) VNode {
    //         const wrapper: *@TypeOf(comp) = @ptrCast(@alignCast(s));
    //         return wrapper.render(tree);
    //     }
    //     pub fn create(allocator: std.mem.Allocator) *anyopaque {
    //         const ptr = allocator.create(@TypeOf(comp)) catch unreachable;
    //         ptr.* = comp;
    //         return ptr;
    //     }
    //     pub fn destroy(allocator: std.mem.Allocator, anyptr: *anyopaque) void {
    //         const ptr: *@TypeOf(comp) = @ptrCast(@alignCast(anyptr));
    //         allocator.destroy(ptr);
    //     }
    // };
    // _ = Wrapper; // autofix

    const key = self.generateUniqueId(if (props.key.len == 0) @typeName(@TypeOf(comp)) else props.key);
    const current_parent = self.state.current_component;

    const component_vnode = self.arena.create(VNode) catch unreachable;
    component_vnode.* = VNode{
        .key = key,
        .ty = .{
            .component = Component{
                .type_name = @typeName(@TypeOf(comp)),
                .parent = current_parent,
            },
        },
        .first_child = null,
    };

    self.state.current_component = component_vnode;
    const node = @constCast(&comp).render(self);
    node.parent = component_vnode;
    component_vnode.first_child = node;
    self.state.current_component = current_parent;

    return component_vnode;
}

pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(self.arena, format, args) catch unreachable;
}

pub fn print(root: *VNode, depth: usize) void {
    for (0..depth) |_| {
        std.debug.print("  ", .{});
    }
    if (root.ty == .element) {
        std.debug.print("{s} {s} {s}\n", .{ root.key, root.ty.element.class, root.ty.element.text });
    } else {
        std.debug.print("{s}\n", .{root.key});
    }

    var node: ?*VNode = root.first_child;
    while (node) |item| {
        _ = print(item, depth + 1);
        node = item.next_sibling;
    }
}

pub fn useRef(comptime T: type) type {
    return struct {
        // value: *T,
        tree: *Self,

        pub fn init(tree: *Self, initial_value: T) @This() {
            // const current_hook_index = tree.current_hook_index;
            std.debug.print("{d}\n", .{initial_value});
            // const ptr: *T = if (tree.current_instance.?.hooks.items.len <= current_hook_index) blk: {
            //     const ptr = tree.gpa.create(T) catch unreachable;
            //     ptr.* = initial_value;
            //     tree.current_instance.?.hooks.append(tree.gpa, Hook{
            //         .ptr = ptr,
            //     }) catch unreachable;
            //     break :blk ptr;
            // } else blk: {
            //     const hook = tree.current_instance.?.hooks.items[current_hook_index];
            //     break :blk @ptrCast(@alignCast(hook.ptr));
            // };

            return .{
                // .value = ptr,
                .tree = tree,
            };
        }

        // pub fn set(this: @This(), new_value: T) void {
        //     this.value.* = new_value;
        //     this.tree.markDirty(this.tree.current_instance.?);
        // }
    };
}

pub const Mutation = union(enum) {
    create_element: struct {
        parent: *VNode,
        child: *VNode,
    },
    remove_child: struct {
        parent: *VNode,
        child: *VNode,
    },
    append_child: struct {
        parent: *VNode,
        child: *VNode,
    },
    insert_before: struct {
        parent: *VNode,
        child: *VNode,
        before: *VNode,
    },
    set_class: struct {
        node: *VNode,
        class: []const u8,
    },
    set_text: struct {
        node: *VNode,
        text: []const u8,
    },
};

pub fn diff(self: *Self, old_self: *Self, old_node: ?*VNode, new_node: ?*VNode, mutations: *std.ArrayList(Mutation)) !void {
    if (old_node == null and new_node == null) {
        return;
    }

    if (old_node == null) {
        try mutations.append(.{
            .create_element = .{
                .parent = new_node.?.parent.?,
                .child = new_node.?,
            },
        });
        return;
    }

    if (new_node == null) {
        std.log.info("{s}", .{old_node.?.key});
        // remove all old nodes
        try mutations.append(.{
            .remove_child = .{
                .parent = old_node.?.parent.?,
                .child = old_node.?,
            },
        });
        return;
    }

    if (!std.mem.eql(u8, old_node.?.key, new_node.?.key)) {
        // replace the node
        try mutations.append(.{
            .remove_child = .{
                .parent = old_node.?.parent.?,
                .child = old_node.?,
            },
        });
        try mutations.append(.{
            .create_element = .{
                .parent = new_node.?.parent.?,
                .child = new_node.?,
            },
        });
    }

    if (@intFromEnum(old_node.?.ty) == @intFromEnum(new_node.?.ty)) {
        switch (old_node.?.ty) {
            .element => {
                const old_element = old_node.?.ty.element;
                const new_element = new_node.?.ty.element;

                if (!std.mem.eql(u8, old_element.class, new_element.class)) {
                    try mutations.append(.{
                        .set_class = .{
                            .node = old_node.?,
                            .class = new_element.class,
                        },
                    });
                }

                if (!std.mem.eql(u8, old_element.text, new_element.text)) {
                    try mutations.append(.{
                        .set_text = .{
                            .node = old_node.?,
                            .text = new_element.text,
                        },
                    });
                }
            },
            .component => {
                const old_component = old_node.?.ty.component;
                const new_component = new_node.?.ty.component;
                if (!std.mem.eql(u8, old_component.type_name, new_component.type_name)) {
                    // replace the node
                    try mutations.append(.{
                        .remove_child = .{
                            .parent = old_node.?.parent.?,
                            .child = old_node.?,
                        },
                    });
                    try mutations.append(.{
                        .create_element = .{
                            .parent = new_node.?.parent.?,
                            .child = new_node.?,
                        },
                    });
                }
            },
        }
    }

    // diff children
    var old_child: ?*VNode = old_node.?.first_child;
    var new_child: ?*VNode = new_node.?.first_child;
    while (old_child != null or new_child != null) {
        try Self.diff(self, old_self, old_child, new_child, mutations);
        if (old_child == null) {
            new_child = new_child.?.next_sibling;
            continue;
        }
        if (new_child == null) {
            old_child = old_child.?.next_sibling;
            continue;
        }
        old_child = old_child.?.next_sibling;
        new_child = new_child.?.next_sibling;
    }
}
