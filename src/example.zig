const Dom = @import("root").Dom;
const std = @import("std");

pub const App = struct {
    something: usize,

    fn onclick(self: *@This()) void {
        _ = self; // autofix
        std.log.debug("click!", .{});
    }

    pub fn render(self: *@This(), t: *Dom) Dom.Node {
        _ = self; // autofix
        const ref = t.useRef(usize, 1);

        return t.div(.{
            .class = "w-200 h-200 bg-red-500",
            .children = &.{
                t.div(.{
                    .key = "crazy henkie",
                    .class = t.fmt("w-100 h-100 bg-blue-500 {d}", .{ref.value.*}),
                }),
                // t.createText("Hello world!"),
                // t.createComponent(App2{
                //     .something = self.something,
                // }, .{}),
                // t.createText("H2222222222"),
                // if (self.something == 69)
                //     t.createComponent(App3{}, .{})
                // else
                //     t.createText("Not 69"),
                // t.createElement(.{
                //     .class = "w-dfdfsdfsd h-100 bg-blue-500",
                // }),
            },
        });
    }
};
