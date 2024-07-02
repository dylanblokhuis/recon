const std = @import("std");
const Self = @This();

const Hook = struct {
    ptr: *anyopaque,
};

const PersistentState = struct {
    known_instances: std.StringArrayHashMap(Instance),
};

gpa: std.mem.Allocator,
arena_allocator: std.heap.ArenaAllocator,
persistent_state: *PersistentState,
// used while rendering to build paths to find existing instances
current_path: std.ArrayListUnmanaged([]const u8),
// used when rendering to find hooks
current_instance: ?*Instance = null,
current_hook_index: usize = 0,

const Instance = struct {
    ptr: *anyopaque,
    hooks: std.ArrayListUnmanaged(Hook),
    render_func_ptr: *const fn (*anyopaque, *Self) Node,
    is_dirty: bool,
    parent: ?*Instance,
    // create_ptr: *const fn (std.mem.Allocator) *anyopaque,
    // destroy_ptr: *const fn (std.mem.Allocator, *anyopaque) void,
};

pub const Node = struct {
    key: []const u8,
    class: []const u8,
    text: []const u8,
    first_child: ?*Node = null,
    next_sibling: ?*Node = null,
    // children: ?[]const Node = null,
};

pub fn createPersistentState(allocator: std.mem.Allocator) !PersistentState {
    return .{
        .known_instances = std.StringArrayHashMap(Instance).init(allocator),
    };
}

pub fn init(allocator: std.mem.Allocator, state: *PersistentState) !Self {
    return Self{
        .gpa = allocator,
        .arena_allocator = std.heap.ArenaAllocator.init(allocator),
        .persistent_state = state,
        .current_path = .{},
    };
}

pub inline fn arena(self: *Self) std.mem.Allocator {
    return self.arena_allocator.allocator();
}

pub fn addPath(self: *Self, path: []const u8) []const u8 {
    self.current_path.append(self.arena(), path) catch unreachable;
    return self.getPath();
}

fn getPath(self: *Self) []const u8 {
    var accumulated_len: usize = 0;
    for (self.current_path.items) |item| {
        accumulated_len += item.len;
        accumulated_len += 1; // for the dot
    }

    const result = self.arena().alloc(u8, accumulated_len) catch unreachable;
    var i: usize = 0;
    for (self.current_path.items) |item| {
        for (item) |c| {
            result[i] = c;
            i += 1;
        }
        result[i] = '/'; // for the slash
        i += 1;
    }
    return result;
}

const InstanceProps = struct {
    key: []const u8 = "",
};
pub fn createInstance(self: *Self, comp: anytype, props: InstanceProps) Node {
    const Wrapper = struct {
        pub fn render(s: *anyopaque, tree: *Self) Node {
            const wrapper: *@TypeOf(comp) = @ptrCast(@alignCast(s));
            return wrapper.render(tree);
        }
        pub fn create(allocator: std.mem.Allocator) *anyopaque {
            const ptr = allocator.create(@TypeOf(comp)) catch unreachable;
            ptr.* = comp;
            return ptr;
        }
        pub fn destroy(allocator: std.mem.Allocator, anyptr: *anyopaque) void {
            const ptr: *@TypeOf(comp) = @ptrCast(@alignCast(anyptr));
            allocator.destroy(ptr);
        }
    };
    _ = Wrapper; // autofix

    const key = if (props.key.len == 0) @typeName(@TypeOf(comp)) else props.key;
    const node = @constCast(&comp).render(self);
    std.log.info("{s}", .{key});
    // const parent = self.current_instance;
    // self.current_instance = .{
    //     .hooks = std.ArrayListUnmanaged(Hook){},
    //     .parent = parent,
    // };

    return node;
    // return .{
    //     .key = key,
    //     .ty = .{
    //         .instance = Instance{
    //             .ptr = @constCast(&comp),
    //             .hooks = std.ArrayListUnmanaged(Hook){},
    //             .render_func_ptr = @constCast(&Wrapper.render),
    //             .is_dirty = true,
    //             .parent = self.current_instance,
    //             // .create_ptr = @constCast(&Wrapper.create),
    //             // .destroy_ptr = @constCast(&Wrapper.destroy),
    //         },
    //     },
    // };
}

pub fn createText(self: *Self, text: []const u8) Node {
    return self.createElement(.{
        .text = text,
    });
}

const ElementProps = struct {
    key: []const u8 = "",
    class: []const u8 = "",
    children: ?[]const Node = null,
};
pub fn createElement(self: *Self, props: ElementProps) Node {
    const key = if (props.key.len == 0) "element" else props.key;

    const parent = self.arena().create(Node) catch unreachable;
    parent.* = .{
        .key = key,
        .class = self.arena().dupe(u8, props.class) catch unreachable,
        .text = self.arena().dupe(u8, props.text) catch unreachable,
    };

    if (props.children) |children| {
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

pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(self.arena(), format, args) catch unreachable;
}

// fn renderInner(self: *Self, node: Node) void {
//     const path = self.addPath(node.key);
//     std.debug.print("{s}\n", .{path});

//     switch (node.ty) {
//         .element => |element| {
//             const maybe_children = element.children;

//             if (maybe_children) |children| {
//                 for (children, 0..) |child, i| {
//                     const path_before = self.current_path.clone(self.arena()) catch unreachable;
//                     _ = self.addPath(std.fmt.allocPrint(self.arena(), "{d}", .{i}) catch unreachable);
//                     Self.renderInner(self, child);
//                     self.current_path = path_before;
//                 }
//             }
//         },
//         .instance => {
//             const instance = self.persistent_state.known_instances.getOrPut(path) catch unreachable;
//             if (!instance.found_existing) {
//                 instance.value_ptr.* = node.ty.instance;
//             }
//             self.current_instance = instance.value_ptr;
//             Self.renderInner(self, instance.value_ptr.render_func_ptr(instance.value_ptr.ptr, self));
//         },
//         .text => {},
//     }
// }

pub fn render(self: *Self, root: Node) void {
    _ = self.arena_allocator.reset(.free_all);
    self.current_path = .{};

    var maybe_first_child = root.first_child;
    while (maybe_first_child)
}

fn markDirty(self: *Self, instance: *Instance) void {
    _ = self; // autofix
    instance.is_dirty = true;
    // if (instance.parent) |parent| {
    //     Self.markDirty(self, parent);
    // }
}

pub fn useRef(comptime T: type) type {
    return struct {
        value: *T,
        tree: *Self,

        pub fn init(tree: *Self, initial_value: T) @This() {
            const current_hook_index = tree.current_hook_index;

            const ptr: *T = if (tree.current_instance.?.hooks.items.len <= current_hook_index) blk: {
                const ptr = tree.gpa.create(T) catch unreachable;
                ptr.* = initial_value;
                tree.current_instance.?.hooks.append(tree.gpa, Hook{
                    .ptr = ptr,
                }) catch unreachable;
                break :blk ptr;
            } else blk: {
                const hook = tree.current_instance.?.hooks.items[current_hook_index];
                break :blk @ptrCast(@alignCast(hook.ptr));
            };

            return .{
                .value = ptr,
                .tree = tree,
            };
        }

        pub fn set(this: @This(), new_value: T) void {
            this.value.* = new_value;
            this.tree.markDirty(this.tree.current_instance.?);
        }
    };
}
