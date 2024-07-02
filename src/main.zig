const std = @import("std");
const recon = @import("root.zig");
const tree = @import("tree2.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    // const r = try recon.init(allocator);

    // var state = try tree.createPersistentState(allocator);

    var tree1 = tree.init(allocator);
    var tree2 = tree.init(allocator);
    const root1 = tree1.createInstance(App{ .something = 69 }, .{});
    const root2 = tree2.createInstance(App{ .something = 420 }, .{});

    var mutations = std.ArrayList(tree.Mutation).init(allocator);
    try tree.diff(&tree2, &tree1, root1, root2, &mutations);

    for (mutations.items) |mutation| {
        switch (mutation) {
            .set_class => |sc| {
                std.log.info("set_class {s}", .{sc.class});
                tree.print(sc.node, 0);
            },
            .remove_child => |rc| {
                std.log.info("remove_child", .{});
                tree.print(rc.child, 0);
            },
            .append_child => |ac| {
                std.log.info("append_child", .{});
                tree.print(ac.child, 0);
            },
            .create_element => |ce| {
                std.log.info("create_element", .{});
                tree.print(ce.child, 0);
            },
            else => {
                std.log.info("{}", .{mutation});
            },
        }
    }
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

    pub fn render(self: *@This(), t: *tree) *tree.VNode {
        _ = tree.useRef(usize).init(t, 1);

        return t.createElement(.{
            .class = "w-200 h-200 bg-red-500",
            .children = &.{
                t.createElement(.{
                    .key = "crazy henkie",
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
                t.createInstance(App2{
                    .something = self.something,
                }, .{}),
                if (self.something == 69)
                    t.createInstance(App3{}, .{})
                else
                    t.createText("Not 69"),
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

    pub fn render(self: *@This(), t: *tree) *tree.VNode {
        // const ref = tree.useRef(u32).init(t, 4);
        // ref.set(ref.value.* + 1);
        _ = tree.useRef(usize).init(t, 10);
        _ = tree.useRef(usize).init(t, 30);

        return t.createElement(.{
            .class = t.fmt("w-200 h-200 bg-red-500 {d}", .{self.something}),
            .children = &.{
                t.createElement(.{
                    // .key = t.fmt("{d}", .{ref.value.*}),
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
                t.createInstance(App3{}, .{}),
            },
        });
    }
};

const App3 = struct {
    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *tree) *tree.VNode {
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
