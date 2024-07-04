const std = @import("std");
const recon = @import("root.zig");
const VDom = @import("vdom.zig").VDom(Instance, Renderer);

const Instance = struct {
    class: []const u8,
    text: []const u8,
};
const Renderer = struct {
    const Self = @This();

    gpa: std.mem.Allocator,

    pub fn createInstance(self: *Self, element: VDom.Element) *Instance {
        const instance = self.gpa.create(Instance) catch unreachable;
        instance.* = .{
            .class = self.gpa.dupe(u8, element.class) catch unreachable,
            .text = self.gpa.dupe(u8, element.text) catch unreachable,
        };
        std.log.info("createInstance {d}", .{@intFromPtr(instance)});
        return instance;
    }

    pub fn appendChild(self: *Self, parent: *Instance, child: *Instance) void {
        _ = self; // autofix
        std.log.info("appendChild {d} {d}", .{ @intFromPtr(parent), @intFromPtr(child) });
    }

    pub fn removeChild(self: *Self, parent: *Instance, child: *Instance) void {
        _ = self; // autofix
        std.log.info("removeChild {d} {d}  - parent {s} | child {s}", .{ @intFromPtr(parent), @intFromPtr(child), parent.class, child.class });
    }

    pub fn insertBefore(self: *Self, parent: *Instance, child: *Instance, before: *Instance) void {
        _ = self; // autofix
        std.log.info("insertBefore {d} {d} {d}", .{ @intFromPtr(parent), @intFromPtr(child), @intFromPtr(before) });
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
    const root1 = tree1.createComponent(App{ .something = 69 }, .{});
    try tree1.diff(&tree2, null, root1, config);

    const root2 = tree2.createComponent(App{ .something = 420 }, .{});

    std.debug.print("\ndiffing tree2\n", .{});
    try tree2.diff(&tree1, root1, root2, config);
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
                }),
                t.createText("Hello world!"),
                t.createComponent(App2{
                    .something = self.something,
                }, .{}),
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
            .class = t.fmt("w-200 h-200 bg-red-500 {d}", .{self.something}),
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
            .class = "w-200 h-200 bg-red-500",
            .children = &.{
                t.createElement(.{
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
            },
        });
    }
};
