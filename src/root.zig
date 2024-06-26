const std = @import("std");
const xev = @import("xev");

const Self = @This();

allocator: std.mem.Allocator,
loop: xev.Loop,
completions: std.heap.MemoryPoolExtra(xev.Completion, .{}),

pub fn init(allocator: std.mem.Allocator) !*Self {
    const loop = try xev.Loop.init(.{});

    const self = try allocator.create(Self);
    self.* = Self{
        .allocator = allocator,
        .loop = loop,
        .completions = std.heap.MemoryPoolExtra(xev.Completion, .{}).init(allocator),
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.loop.deinit();
    self.completions.deinit();
}

pub inline fn run(self: *Self) !void {
    try self.loop.run(.until_done);
}

pub fn spawn(self: *Self, func: anytype, args: anytype) !void {
    const c = try self.completions.create();

    const Cb = struct {
        outer: *Self,
        args: @TypeOf(args),
        func: *anyopaque,

        pub fn cb(
            ud: ?*anyopaque,
            _: *xev.Loop,
            completion: *xev.Completion,
            _: xev.Result,
        ) xev.CallbackAction {
            const callback: *@This() = @ptrCast(@alignCast(ud));
            defer callback.outer.allocator.destroy(callback);
            defer callback.outer.completions.destroy(completion);

            const func_ptr: *@TypeOf(func) = @ptrCast(@alignCast(callback.func));
            _ = @call(.auto, func_ptr, args);

            return .disarm;
        }
    };

    const ptr = try self.allocator.create(Cb);
    ptr.* = Cb{
        .outer = self,
        .args = args,
        .func = @constCast(&func),
    };

    self.loop.timer(c, 0, ptr, Cb.cb);
}
