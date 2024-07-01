const std = @import("std");
const recon = @import("root.zig");
const tree = @import("tree.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const r = try recon.init(allocator);

    var state = try tree.createPersistentState(allocator);

    var t = try tree.init(allocator, &state);

    t.render(
        t.createInstance(App{}, .{}),
    );
    t.render(
        t.createInstance(App{}, .{}),
    );

    try r.spawn(doSomeWork, .{"Hen"});
    try r.spawn(doSomeWork, .{"Henkie"});

    try r.run();
}

fn doSomeWork(henkie: []const u8) []const u8 {
    std.log.debug("Doing some work! with {s}", .{henkie});
    // do some work
    return "Hello, World!";
}

const App = struct {
    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *tree) tree.Node {
        _ = self; // autofix

        return t.createElement(.{
            .class = "w-200 h-200 bg-red-500",
            .children = &.{
                t.createElement(.{
                    .key = "crazy henkie",
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
                t.createInstance(App2{}, .{}),
                t.createInstance(App2{}, .{}),
                t.createElement(.{
                    .key = "yooo",
                    .class = "w-100 h-100 bg-blue-500",
                    .children = &.{
                        t.createText("Whats up!"),
                    },
                }),
            },
        });
    }
};

const App2 = struct {
    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *tree) tree.Node {
        _ = self; // autofix
        const ref = tree.useRef(u32).init(t, 4);
        // ref.set(ref.value.* + 1);

        return t.createElement(.{
            .class = "w-200 h-200 bg-red-500",
            .children = &.{
                t.createElement(.{
                    .key = t.fmt("{d}", .{ref.value.*}),
                    .class = "w-100 h-100 bg-blue-500",
                }),
                t.createText("Hello world!"),
            },
        });
    }
};
