const std = @import("std");
const Self = @This();
const Allocator = std.mem.Allocator;

const State = struct {
    current_component: ?*VNode = null,
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
        var maybe_parent = current.ty.component.parent;
        while (maybe_parent) |parent| {
            key.appendSlice(parent.key) catch unreachable;
            // key.append('/') catch unreachable;
            maybe_parent = parent.ty.component.parent;
        }
        key.appendSlice(current.key) catch unreachable;
        // key.append('/') catch unreachable;
        // key.appendSlice(my_key) catch unreachable;
        return key.toOwnedSlice() catch unreachable;
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

    const this_key = if (props.key.len == 0) @typeName(@TypeOf(comp)) else props.key;
    const key = self.generateUniqueId(this_key);

    const current_parent = self.state.current_component;

    const componentVNode = self.arena.create(VNode) catch unreachable;
    componentVNode.* = VNode{
        .key = key,
        .ty = .{
            .component = Component{
                .parent = current_parent,
            },
        },
        .first_child = null,
    };

    self.state.current_component = componentVNode;
    const node = @constCast(&comp).render(self);
    self.state.current_component = current_parent;
    componentVNode.first_child = node;

    return componentVNode;
}

pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(self.arena, format, args) catch unreachable;
}

pub fn print(root: *VNode, depth: usize) void {
    for (0..depth) |i| {
        _ = i; // autofix
        std.debug.print("  ", .{});
    }
    std.debug.print("{s}\n", .{root.key});

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
