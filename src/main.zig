const std = @import("std");
const recon = @import("root.zig");
const c = @cImport({
    @cInclude("yoga/Yoga.h");
    @cInclude("raylib.h");
});

const Instance = Renderer.NodeId;
const Transform = struct {
    position: [3]f32,
    // rotation: @Vector(3, f32),
    // scale: @Vector(3, f32),
};
const Element = union(enum) {
    pub const Group = struct {
        transform: Transform,
    };
    pub const Object = struct {
        model: c.Model,
        transform: Transform,
    };

    div: struct {
        class: []const u8,
        text: []const u8 = "",
    },
    group: Group,
    object: Object,

    /// we need to implement clone whenever we go from an arena to a general purpose allocator
    // pub fn clone(self: Element, gpa: std.mem.Allocator) !Element {
    //     switch (self) {
    //         .div => |div| {
    //             return .{
    //                 .div = .{
    //                     .class = try gpa.dupe(u8, div.class),
    //                     .text = try gpa.dupe(u8, div.text),
    //                 },
    //             };
    //         },
    //     }
    // }

    /// implement eql here to compare elements in the diffing process
    pub fn isEql(self: Element, other: Element) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
            return false;
        }

        switch (self) {
            .div => |div| {
                return std.mem.eql(u8, div.class, other.div.class) and
                    std.mem.eql(u8, div.text, other.div.text);
            },
            else => {
                return std.meta.eql(self, other);
            },
            // .group => |group| {
            //     return std.meta.eql(group, other.group);
            // },
            // .object => |object| {
            //     return std.meta.eql(object, other.object);
            // },
        }

        return false;
    }
};
pub const VDom = @import("vdom.zig").VDom(Instance, Renderer, Element);

/// wrapper around VDom calls to make it more ergonomic
pub const Dom = struct {
    const Self = @This();
    pub const Node = *VDom.VNode;

    vdom: *VDom,

    const DivProps = struct {
        key: []const u8 = "",
        class: []const u8 = "",
        text: []const u8 = "",
        children: VDom.Children = null,
    };

    pub inline fn div(self: Self, props: DivProps) Node {
        return self.vdom.createElement(props.key, .{
            .div = .{
                .class = props.class,
                .text = props.text,
            },
        }, props.children);
    }

    const GroupProps = struct {
        key: []const u8 = "",
        transform: Transform,
        children: VDom.Children = null,
    };
    pub inline fn group(self: Self, props: GroupProps) Node {
        return self.vdom.createElement(props.key, .{
            .group = .{
                .transform = props.transform,
            },
        }, props.children);
    }

    const ObjectProps = struct {
        key: []const u8 = "",
        model: c.Model,
        transform: Transform,
    };

    pub inline fn object(self: Self, props: ObjectProps) Node {
        return self.vdom.createElement(props.key, .{
            .object = .{
                .model = props.model,
                .transform = props.transform,
            },
        }, null);
    }

    pub inline fn comp(self: Self, comptime component: anytype, props: VDom.ComponentProps) Node {
        const Wrapper = struct {
            outer: *@TypeOf(component),

            pub inline fn render(this: *@This(), tree: *VDom) *VDom.VNode {
                return this.outer.render(Dom{ .vdom = tree });
            }
        };

        return self.vdom.createComponent(Wrapper{ .outer = @constCast(&component) }, props);
    }

    pub inline fn fmt(self: Self, comptime format: []const u8, args: anytype) []u8 {
        return self.vdom.fmt(format, args);
    }

    pub inline fn useRef(self: Self, comptime T: type, initial_value: T) VDom.useRef(T) {
        return VDom.useRef(T).init(self.vdom, initial_value);
    }

    pub fn UseState(
        comptime T: type,
    ) type {
        return struct {
            ref: VDom.useRef(T),

            pub fn get(self: @This()) T {
                return self.ref.value.*;
            }

            pub fn set(self: @This(), value: T) void {
                self.ref.value.* = value;

                // mark this compoennt and its parents as dirty
                self.ref.tree.component_map.markDirty(self.ref.tree.state.current_component.?.key);
                var parent = self.ref.tree.state.current_component.?.parent;
                while (parent) |p| {
                    self.ref.tree.component_map.markDirty(p.key);
                    parent = p.parent;
                }
            }
        };
    }

    pub fn useState(self: Self, comptime T: type, initial_value: T) UseState(T) {
        return UseState(T){
            .ref = self.useRef(T, initial_value),
        };
    }
};

const Renderer = struct {
    const Self = @This();
    const NodeType = union(enum) {
        ui: struct {},
    };
    pub const NodeId = usize;
    const Children = std.ArrayListUnmanaged(NodeId);
    const Node = struct {
        ty: NodeType,
        children: Children,
        parent: ?NodeId,
    };

    gpa: std.mem.Allocator,
    tree: std.MultiArrayList(Node),
    free_list: std.ArrayListUnmanaged(NodeId),

    pub fn init(gpa: std.mem.Allocator) Self {
        return Self{
            .gpa = gpa,
            .tree = .{},
            .free_list = .{},
        };
    }

    pub fn createInstance(self: *Self, element: VDom.Element) Instance {
        _ = element; // autofix

        const maybe_freelist_id = self.free_list.popOrNull();

        const node_id = if (maybe_freelist_id) |id| id else self.tree.addOne(self.gpa) catch unreachable;
        self.tree.set(node_id, Node{
            .ty = .{
                .ui = .{},
            },
            .children = .{},
            .parent = null,
        });

        return node_id;

        // const ref = c.YGNodeNew();

        // const data = self.gpa.create(Element) catch unreachable;
        // data.* = element.clone(self.gpa) catch unreachable;
        // c.YGNodeSetContext(ref, data);
        // std.log.info("createInstance {d}", .{@intFromPtr(ref)});
        // return ref.?;
    }

    pub fn appendChild(self: *Self, parent: Instance, child: Instance) void {
        const children: *Children = &self.tree.items(.children)[parent];
        const child_parent: *?NodeId = &self.tree.items(.parent)[child];

        children.append(self.gpa, child) catch unreachable;
        child_parent.* = parent;

        // const child_count = c.YGNodeGetChildCount(parent);
        // c.YGNodeInsertChild(parent, child, child_count);
        // std.log.info("appendChild {d} {d}", .{ @intFromPtr(parent), @intFromPtr(child) });
    }

    pub fn removeChild(self: *Self, parent: Instance, child: Instance) void {
        const children: *Children = &self.tree.items(.children)[parent];
        _ = children.orderedRemove(child);

        // free recusively
        const child_children: *Children = &self.tree.items(.children)[child];
        while (child_children.popOrNull()) |item| {
            self.removeChild(child, item);
        }

        // remove node from tree
        self.tree.set(child, undefined);
        self.free_list.append(self.gpa, child) catch unreachable;
        // TODO: deallocate stuff inside the instance
    }

    pub fn insertBefore(self: *Self, parent: Instance, child: Instance, before: Instance) void {
        const children: *Children = &self.tree.items(.children)[parent];
        children.insert(self.gpa, before, child) catch unreachable;
        const child_parent_ptr: *?NodeId = &self.tree.items(.parent)[child];
        child_parent_ptr.* = parent;
    }

    pub fn printTree(self: *Self, root_node: Instance) void {
        const Inner = struct {
            pub fn print(this: *Self, node: Instance, depth: usize) void {
                const list = this.tree.items(.children)[node];

                for (0..depth) |_| {
                    std.debug.print("  ", .{});
                }

                // const props: *Element = @ptrCast(@alignCast(c.YGNodeGetContext(node).?));
                // _ = props; // autofix
                // std.debug.print("Node {s} {s}\n", .{ props.class, props.text });
                std.debug.print("Node \n", .{});

                for (list.items) |child| {
                    // const child = c.YGNodeGetChild(node, i).?;
                    @This().print(this, child, depth + 1);
                }
            }
        };

        Inner.print(self, root_node, 0);
    }

    pub fn updateNode(self: *Self, node: Instance, element: VDom.Element) void {
        _ = node; // autofix
        _ = element; // autofix
        _ = self; // autofix
        // std.log.info("updateNode {d} {any}", .{ @intFromPtr(node), element });
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var renderer = Renderer.init(allocator);
    const config = VDom.UserConfig{
        .renderer = &renderer,
        .create_instance_fn = Renderer.createInstance,
        .append_child_fn = Renderer.appendChild,
        .remove_child_fn = Renderer.removeChild,
        .insert_before_fn = Renderer.insertBefore,
        .update_node_fn = Renderer.updateNode,
    };
    var map = VDom.ComponentMap.init(allocator);

    c.InitWindow(1280, 720, "recon");
    c.SetTargetFPS(0);

    var prev_tree: VDom = VDom.init(allocator, &map);
    var prev_root: ?*VDom.VNode = null;
    var prev_arena: ?std.heap.ArenaAllocator = null;

    while (!c.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var tree = VDom.init(arena.allocator(), &map);
        const dom = Dom{ .vdom = &tree };
        const root = dom.comp(@import("example.zig").App{ .something = 420 }, .{});
        try tree.diff(&prev_tree, prev_root, root, config);

        {
            c.BeginDrawing();
            defer c.EndDrawing();
            c.ClearBackground(c.BLACK);

            const fps = c.GetFPS();
            const str = try std.fmt.allocPrintZ(arena.allocator(), "FPS: {d}", .{fps});
            c.DrawText(str, 190, 200, 20, c.WHITE);

            if (c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT)) {
                renderer.printTree(root.instance.?);
            }
        }

        if (prev_arena) |*prev| {
            prev.deinit();
        }
        prev_root = root;
        prev_tree = tree;
        prev_arena = arena;
    }
}
