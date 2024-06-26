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
    // create_ptr: *const fn (std.mem.Allocator) *anyopaque,
    // destroy_ptr: *const fn (std.mem.Allocator, *anyopaque) void,
};

pub const NodeType = union(enum) {
    element: struct {
        class: []const u8,
        children: ?[]const Node = null,
    },
    text: []const u8,
    instance: Instance,
};
pub const Node = struct {
    key: []const u8,
    ty: NodeType,
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
    _ = self; // autofix
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

    const key = if (props.key.len == 0) @typeName(@TypeOf(comp)) else props.key;
    return .{
        .key = key,
        .ty = .{
            .instance = Instance{
                .ptr = @constCast(&comp),
                .hooks = std.ArrayListUnmanaged(Hook){},
                .render_func_ptr = @constCast(&Wrapper.render),
                // .create_ptr = @constCast(&Wrapper.create),
                // .destroy_ptr = @constCast(&Wrapper.destroy),
            },
        },
    };
}

pub fn createText(self: *Self, text: []const u8) Node {
    _ = self; // autofix
    return .{
        .key = text,
        .ty = .{
            .text = text,
        },
    };
}

const ElementProps = struct {
    key: []const u8 = "",
    class: []const u8 = "",
    children: ?[]const Node = null,
};
pub fn createElement(self: *Self, props: ElementProps) Node {
    const key = if (props.key.len == 0) "element" else props.key;

    const children: ?[]const Node = if (props.children) |children| blk: {
        const stable_ptrs = self.arena().alloc(Node, children.len) catch unreachable;

        for (children, 0..) |child, i| {
            stable_ptrs[i] = child;
        }

        break :blk stable_ptrs;
    } else blk: {
        break :blk null;
    };

    return .{
        .key = key,
        .ty = .{
            .element = .{
                .class = props.class,
                .children = children,
            },
        },
    };
}

pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(self.arena(), format, args) catch unreachable;
}

fn renderInner(self: *Self, node: Node) void {
    const path = self.addPath(node.key);
    std.debug.print("{s}\n", .{path});

    switch (node.ty) {
        .element => |element| {
            const maybe_children = element.children;

            if (maybe_children) |children| {
                for (children, 0..) |child, i| {
                    const path_before = self.current_path.clone(self.arena()) catch unreachable;
                    _ = self.addPath(std.fmt.allocPrint(self.arena(), "{d}", .{i}) catch unreachable);
                    Self.renderInner(self, child);
                    self.current_path = path_before;
                }
            }
        },
        .instance => {
            const instance = self.persistent_state.known_instances.getOrPut(path) catch unreachable;
            if (!instance.found_existing) {
                instance.value_ptr.* = node.ty.instance;
            }
            self.current_instance = instance.value_ptr;
            Self.renderInner(self, instance.value_ptr.render_func_ptr(instance.value_ptr.ptr, self));
        },
        .text => {},
    }
}

pub fn render(self: *Self, root: Node) void {
    _ = self.arena_allocator.reset(.free_all);
    self.current_path = .{};

    renderInner(self, root);
}

pub fn useRef(comptime T: type) type {
    return struct {
        value: *T,

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
                break :blk @as(*T, @ptrCast(@alignCast(hook.ptr)));
            };

            return .{
                .value = ptr,
            };
        }

        pub fn set(this: @This(), new_value: T) void {
            this.value.* = new_value;
        }
    };
}
