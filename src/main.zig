const std = @import("std");
const recon = @import("root.zig");
const VDom = @import("vdom.zig").VDom(Instance, Renderer);
const c = @cImport({
    @cInclude("yoga/Yoga.h");
});

const Instance = c.struct_YGNode;
const InstanceData = struct {
    class: []const u8,
    text: []const u8,
};
const Renderer = struct {
    const Self = @This();

    gpa: std.mem.Allocator,

    pub fn createInstance(self: *Self, element: VDom.Element) *Instance {
        const ref = c.YGNodeNew();

        const data = self.gpa.create(InstanceData) catch unreachable;
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
                const ptr: *InstanceData = @ptrCast(@alignCast(c.YGNodeGetContext(child)));
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

                const props: *InstanceData = @ptrCast(@alignCast(c.YGNodeGetContext(node).?));
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
    // const r = try recon.init(allocator);

    // var state = try tree.createPersistentState(allocator);
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

    var tree1 = VDom.init(allocator, &map);
    var tree2 = VDom.init(allocator, &map);
    const root1 = tree1.createComponent(App{ .something = 420 }, .{});
    try tree1.diff(&tree2, null, root1, config);

    const root2 = tree2.createComponent(App{ .something = 69 }, .{});

    std.debug.print("\ndiffing tree2\n", .{});
    try tree2.diff(&tree1, root1, root2, config);

    config.renderer.printTree(root2.instance.?);
}

fn doSomeWork(henkie: []const u8) []const u8 {
    std.log.debug("Doing some work! with {s}", .{henkie});
    // do some work
    return "Hello, World!";
}

const App = struct {
    something: usize,

    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *VDom) *VDom.VNode {
        const ref = VDom.useRef(usize).init(t, 1);

        return t.createElement(.{
            .class = "w-200 h-200 bg-red-500",
            .children = &.{
                t.createElement(.{
                    .key = "crazy henkie",
                    .class = t.fmt("w-100 h-100 bg-blue-500 {d}", .{ref.value.*}),
                    .children = &.{
                        t.createElement(.{
                            .class = "w-50 h-50 bg-green-500",
                        }),
                    },
                }),
                t.createText("Hello world!"),
                t.createComponent(App2{
                    .something = self.something,
                }, .{}),
                t.createText("H2222222222"),
                if (self.something == 69)
                    t.createComponent(App3{}, .{})
                else
                    t.createText("Not 69"),
                t.createElement(.{
                    .class = "w-dfdfsdfsd h-100 bg-blue-500",
                }),
            },
        });
    }
};

const App2 = struct {
    something: usize,

    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *VDom) *VDom.VNode {
        // const ref = tree.useRef(u32).init(t, 4);
        // ref.set(ref.value.* + 1);
        _ = VDom.useRef(usize).init(t, 10);
        _ = VDom.useRef(usize).init(t, 30);

        return t.createElement(.{
            .class = t.fmt("APP2 Baby! w-200 h-200 bg-red-500 {d}", .{self.something}),
            .children = &.{
                t.createElement(.{
                    // .key = t.fmt("{d}", .{ref.value.*}),
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
                t.createComponent(App3{}, .{}),
            },
        });
    }
};

const App3 = struct {
    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *VDom) *VDom.VNode {
        _ = self; // autofix

        return t.createElement(.{
            .class = "APP3 BABY w-200 h-200 bg-red-500",
            .children = &.{
                t.createElement(.{
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
            },
        });
    }
};
