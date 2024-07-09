const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn VDom(Instance: type, Renderer: type, ElementT: type) type {
    return struct {
        const Self = @This();

        pub const Element = ElementT;

        const State = struct {
            current_component: ?*VNode = null,
            seen_components: std.StringArrayHashMapUnmanaged(usize) = .{},
            current_hook_index: usize = 0,
        };

        const ComponentState = struct {
            pub const Hook = struct {
                ptr: *anyopaque,
            };
            dirty: bool,
            hooks: std.ArrayList(Hook),
        };
        pub const ComponentMap = struct {
            gpa: Allocator,
            map: std.StringArrayHashMap(ComponentState),

            pub fn init(gpa: Allocator) @This() {
                return @This(){
                    .gpa = gpa,
                    .map = std.StringArrayHashMap(ComponentState).init(gpa),
                };
            }

            pub fn track(self: *@This(), component_key: []const u8) void {
                _ = self.map.getOrPutValue(component_key, .{
                    .dirty = false,
                    .hooks = std.ArrayList(ComponentState.Hook).init(self.gpa),
                }) catch unreachable;
            }

            pub fn getState(self: *@This(), component_key: []const u8) *ComponentState {
                return self.map.getPtr(component_key).?;
            }

            pub fn markDirty(self: *@This(), component_key: []const u8) void {
                const entry = self.map.getPtr(component_key).?;
                entry.dirty = true;
            }

            pub fn getOrPutHook(self: *@This(), component_key: []const u8, hook_index: usize, T: type, initial_value: T) *T {
                const entry = self.map.getPtr(component_key).?;

                if (entry.hooks.items.len <= hook_index) {
                    const ptr = self.gpa.create(T) catch unreachable;
                    ptr.* = initial_value;
                    entry.hooks.append(ComponentState.Hook{
                        .ptr = ptr,
                    }) catch unreachable;
                    return ptr;
                }

                return @ptrCast(@alignCast(entry.hooks.items[hook_index].ptr));
            }
        };

        arena: Allocator,
        state: State,
        component_map: *ComponentMap,

        pub fn init(arena: Allocator, component_map: *ComponentMap) Self {
            return Self{
                .arena = arena,
                .state = .{},
                .component_map = component_map,
            };
        }

        pub const Component = struct {
            type_name: []const u8,
            parent: ?*VNode,
        };

        pub const VNodeType = union(enum) {
            element: Element,
            component: Component,
        };

        pub const VNode = struct {
            key: []const u8,
            ty: VNodeType,
            //
            instance: ?*Instance = null,
            parent: ?*VNode = null,
            first_child: ?*VNode = null,
            next_sibling: ?*VNode = null,
        };

        pub fn createText(self: *Self, text: []const u8) *VNode {
            return self.createElement(.{
                .key = "text",
                .text = text,
            });
        }

        pub const Children = ?[]const *VNode;
        pub fn createElement(self: *Self, el_key: []const u8, el: Element, child_nodes: Children) *VNode {
            const key = if (el_key.len == 0) "element" else el_key;

            const parent = self.arena.create(VNode) catch unreachable;
            parent.* = VNode{
                .key = key,
                .ty = .{
                    .element = el,
                    //     .class = self.arena.dupe(u8, props.class) catch unreachable,
                    //     .text = self.arena.dupe(u8, props.text) catch unreachable,
                    // },
                },
            };

            if (child_nodes) |stack_children| {
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
        pub const ComponentProps = struct {
            key: []const u8 = "",
        };
        pub fn createComponent(self: *Self, comptime comp: anytype, props: ComponentProps) *VNode {
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
            self.component_map.track(component_vnode.key);
            self.state.current_hook_index = 0;
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

        /// a pointer thats stable across renders, aslong as the order of the hooks dont change inbetween renders
        pub fn useRef(comptime T: type) type {
            return struct {
                value: *T,
                tree: *Self,

                pub fn init(tree: *Self, initial_value: T) @This() {
                    const component_key = tree.state.current_component.?.key;
                    const ptr = tree.component_map.getOrPutHook(component_key, tree.state.current_hook_index, T, initial_value);
                    tree.state.current_hook_index += 1;

                    return .{
                        .value = ptr,
                        .tree = tree,
                    };
                }
            };
        }

        pub const UserConfig = struct {
            renderer: *Renderer,
            create_instance_fn: *const fn (self: *Renderer, node: Element) *Instance,
            append_child_fn: *const fn (self: *Renderer, parent: *Instance, child: *Instance) void,
            remove_child_fn: *const fn (self: *Renderer, parent: *Instance, child: *Instance) void,
            insert_before_fn: *const fn (self: *Renderer, parent: *Instance, child: *Instance, before: *Instance) void,
            update_node_fn: *const fn (self: *Renderer, instance: *Instance, node: Element) void,
        };

        pub fn diff(self: *Self, old_self: *Self, old_node: ?*VNode, new_node: ?*VNode, config: UserConfig) !void {
            // Case 1: Both nodes are null, nothing to do
            if (old_node == null and new_node == null) {
                return;
            }

            // Case 2: New node exists, old node doesn't (addition)
            if (old_node == null and new_node != null) {
                try createNewNodeTree(new_node.?, config);
                return;
            }

            // Case 3: Old node exists, new node doesn't (removal)
            if (old_node != null and new_node == null) {
                removeOldNodeTree(old_node.?, config);
                return;
            }

            // Case 4: Both nodes exist, need to update
            if (old_node != null and new_node != null) {
                // If the node types are different, replace the old with the new
                if (@intFromEnum(old_node.?.ty) != @intFromEnum(new_node.?.ty)) {
                    removeOldNodeTree(old_node.?, config);
                    try createNewNodeTree(new_node.?, config);
                    return;
                }

                // Update the node based on its type
                switch (new_node.?.ty) {
                    .element => |new_element| {
                        if (new_element.isEql(old_node.?.ty.element) == false) {
                            config.update_node_fn(config.renderer, old_node.?.instance.?, new_element);
                        }

                        new_node.?.instance = old_node.?.instance;

                        // Diff children
                        try diffChildren(old_self, old_node.?, new_node.?, config);
                    },
                    .component => |_| {
                        const state = self.component_map.getState(new_node.?.key);
                        if (!state.dirty) {
                            new_node.?.instance = old_node.?.instance;
                            return;
                        }

                        // Diff the rendered output of the component
                        try diff(self, old_self, old_node.?.first_child, new_node.?.first_child, config);
                        new_node.?.instance = new_node.?.first_child.?.instance;
                        state.dirty = false;
                    },
                }
            }
        }

        fn createNewNodeTree(node: *VNode, config: UserConfig) !void {
            switch (node.ty) {
                .element => |element| {
                    node.instance = config.create_instance_fn(config.renderer, element);

                    var child = node.first_child;
                    while (child) |child_node| : (child = child_node.next_sibling) {
                        try createNewNodeTree(child_node, config);
                        if (child_node.ty == .element) {
                            config.append_child_fn(config.renderer, node.instance.?, child_node.instance.?);
                        }
                    }
                },
                .component => |_| {
                    try createNewNodeTree(node.first_child.?, config);
                    node.instance = node.first_child.?.instance;

                    // root node doesn't have a parent
                    if (node.parent) |parent| {
                        config.append_child_fn(config.renderer, parent.instance.?, node.first_child.?.instance.?);
                    }
                },
            }
        }

        fn removeOldNodeTree(node: *VNode, config: UserConfig) void {
            switch (node.ty) {
                .element => |_| {
                    config.remove_child_fn(config.renderer, node.parent.?.instance.?, node.instance.?);
                },
                .component => |_| {
                    // i think this is valid due to how we are setting the first child instance as the component instance
                    config.remove_child_fn(config.renderer, node.parent.?.instance.?, node.instance.?);
                },
            }
        }

        fn diffChildren(old_self: *Self, old_parent: *VNode, new_parent: *VNode, config: UserConfig) anyerror!void {
            var old_child: ?*VNode = old_parent.first_child;
            var new_child: ?*VNode = new_parent.first_child;
            var last_stable_child: ?*VNode = null;

            while (old_child != null or new_child != null) {
                if (old_child == null) {
                    // Add new child
                    try createNewNodeTree(new_child.?, config);
                    if (last_stable_child) |stable| {
                        config.insert_before_fn(config.renderer, new_parent.instance.?, new_child.?.instance.?, stable.next_sibling.?.instance.?);
                    } else {
                        config.append_child_fn(config.renderer, new_parent.instance.?, new_child.?.instance.?);
                    }
                    last_stable_child = new_child;
                    new_child = new_child.?.next_sibling;
                } else if (new_child == null) {
                    // Remove old child
                    const next = old_child.?.next_sibling;
                    removeOldNodeTree(old_child.?, config);
                    old_child = next;
                } else if (std.mem.eql(u8, old_child.?.key, new_child.?.key)) {
                    // Keys match, update existing child
                    try old_self.diff(old_self, old_child, new_child, config);
                    last_stable_child = new_child;
                    old_child = old_child.?.next_sibling;
                    new_child = new_child.?.next_sibling;
                } else {
                    // Keys don't match, insert new before old
                    try createNewNodeTree(new_child.?, config);
                    config.insert_before_fn(config.renderer, new_parent.instance.?, new_child.?.instance.?, old_child.?.instance.?);
                    last_stable_child = new_child;
                    new_child = new_child.?.next_sibling;
                }
            }
        }
    };
}
