const std = @import("std");
const recon = @import("root.zig");
const c = @cImport({
    @cInclude("yoga/Yoga.h");
    @cInclude("raylib.h");
});

const Instance = c.struct_YGNode;
const Element = union(enum) {
    div: struct {
        class: []const u8,
        text: []const u8 = "",
    },

    /// we need to implement clone whenever we go from an arena to a general purpose allocator
    pub fn clone(self: Element, gpa: std.mem.Allocator) !Element {
        switch (self) {
            .div => |div| {
                return .{
                    .div = .{
                        .class = try gpa.dupe(u8, div.class),
                        .text = try gpa.dupe(u8, div.text),
                    },
                };
            },
        }
    }

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

    const Props = struct {
        key: []const u8 = "",
        class: []const u8 = "",
        text: []const u8 = "",
        children: VDom.Children = null,
    };

    pub inline fn div(self: Self, props: Props) Node {
        return self.vdom.createElement(props.key, .{
            .div = .{
                .class = props.class,
                .text = props.text,
            },
        }, props.children);
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

    gpa: std.mem.Allocator,

    pub fn createInstance(self: *Self, element: VDom.Element) *Instance {
        const ref = c.YGNodeNew();

        const data = self.gpa.create(Element) catch unreachable;
        data.* = element.clone(self.gpa) catch unreachable;
        c.YGNodeSetContext(ref, data);
        std.log.info("createInstance {d}", .{@intFromPtr(ref)});
        return ref.?;
    }

    pub fn appendChild(self: *Self, parent: *Instance, child: *Instance) void {
        _ = self; // autofix
        const child_count = c.YGNodeGetChildCount(parent);
        c.YGNodeInsertChild(parent, child, child_count);
        std.log.info("appendChild {d} {d}", .{ @intFromPtr(parent), @intFromPtr(child) });
    }

    pub fn removeChild(self: *Self, parent: *Instance, child: *Instance) void {
        // std.log.info("removeChild {d} {d}  - parent {s} | child {s}", .{ @intFromPtr(parent), @intFromPtr(child), parent.class, child.class });
        std.log.info("removeChild {d} {d}", .{ @intFromPtr(parent), @intFromPtr(child) });

        const child_count = c.YGNodeGetChildCount(parent);
        for (0..child_count) |i| {
            const node = c.YGNodeGetChild(parent, i).?;
            if (node == child) {
                c.YGNodeRemoveChild(parent, child);
                const ptr: *Element = @ptrCast(@alignCast(c.YGNodeGetContext(child)));
                self.gpa.destroy(ptr);
                c.YGNodeFree(child);
                return;
            }
        }
    }

    pub fn insertBefore(self: *Self, parent: *Instance, child: *Instance, before: *Instance) void {
        _ = self; // autofix
        std.log.info("insertBefore {d} {d} {d}", .{ @intFromPtr(parent), @intFromPtr(child), @intFromPtr(before) });

        const children_count = c.YGNodeGetChildCount(parent);
        std.debug.assert(children_count > 0);

        for (0..children_count) |i| {
            const curr_child = c.YGNodeGetChild(parent, i).?;
            if (curr_child == before) {
                if (c.YGNodeGetParent(child) == parent) {
                    c.YGNodeRemoveChild(parent, child);
                }
                c.YGNodeInsertChild(parent, child, i);
                return;
            }
        }
    }

    pub fn printTree(self: *Self, root_node: *Instance) void {
        _ = self; // autofix

        const Inner = struct {
            pub fn print(node: c.YGNodeRef, depth: usize) void {
                const children = c.YGNodeGetChildCount(node);

                for (0..depth) |_| {
                    std.debug.print("  ", .{});
                }

                const props: *Element = @ptrCast(@alignCast(c.YGNodeGetContext(node).?));
                _ = props; // autofix
                // std.debug.print("Node {s} {s}\n", .{ props.class, props.text });
                std.debug.print("Node \n", .{});

                for (0..children) |i| {
                    const child = c.YGNodeGetChild(node, i).?;
                    @This().print(child, depth + 1);
                }
            }
        };

        Inner.print(root_node, 0);
    }

    pub fn updateNode(self: *Self, node: *Instance, element: VDom.Element) void {
        _ = self; // autofix
        std.log.info("updateNode {d} {any}", .{ @intFromPtr(node), element });
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var renderer = Renderer{
        .gpa = allocator,
    };
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
