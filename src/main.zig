const std = @import("std");
const recon = @import("root.zig");
const c = @cImport({
    @cInclude("yoga/Yoga.h");
    @cInclude("raylib.h");
});

const Instance = c.struct_YGNode;
const Element = struct {
    class: []const u8,
    text: []const u8 = "",
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
            .class = props.class,
            .text = props.text,
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
        data.* = .{
            .class = self.gpa.dupe(u8, element.class) catch unreachable,
            .text = self.gpa.dupe(u8, element.text) catch unreachable,
        };
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
                std.debug.print("Node {s} {s}\n", .{ props.class, props.text });

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

    c.InitWindow(1440, 900, "recon");
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

fn doSomeWork(henkie: []const u8) []const u8 {
    std.log.debug("Doing some work! with {s}", .{henkie});
    // do some work
    return "Hello, World!";
}

// const App2 = struct {
//     something: usize,

//     fn onclick(self: *@This()) void {
//         _ = self; // autofix
//         std.log.debug("click!", .{});
//     }

//     pub fn render(self: *@This(), t: *VDom) *VDom.VNode {
//         // const ref = tree.useRef(u32).init(t, 4);
//         // ref.set(ref.value.* + 1);
//         _ = VDom.useRef(usize).init(t, 10);
//         _ = VDom.useRef(usize).init(t, 30);

//         return t.createElement(.{
//             .class = t.fmt("APP2 Baby! w-200 h-200 bg-red-500 {d}", .{self.something}),
//             .children = &.{
//                 t.createElement(.{
//                     // .key = t.fmt("{d}", .{ref.value.*}),
//                     .class = "w-100 h-100 bg-blue-500",
//                 }),
//                 t.createText("Hello world!"),
//                 t.createComponent(App3{}, .{}),
//             },
//         });
//     }
// };

// const App3 = struct {
//     fn onclick(self: *@This()) void {
//         _ = self; // autofix
//         std.log.debug("click!", .{});
//     }

//     pub fn render(self: *@This(), t: *VDom) *VDom.VNode {
//         _ = self; // autofix

//         return t.createElement(.{
//             .class = "APP3 BABY w-200 h-200 bg-red-500",
//             .children = &.{
//                 t.createElement(.{
//                     .class = "w-100 h-100 bg-blue-500",
//                 }),
//                 t.createText("Hello world!"),
//             },
//         });
//     }
// };
