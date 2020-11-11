const Allocator = @import("std").mem.Allocator;
const Event = @import("events.zig").Event;

pub const Data = struct {
    allocator: ?*Allocator,
    content: []const u8,

    pub fn to_event(allocator: ?*Allocator, content: []const u8) Event {
        return Event{ .Data = Data{ .allocator = allocator, .content = content } };
    }

    pub fn deinit(self: Data) void {
        if (self.allocator != null) {
            self.allocator.?.free(self.content);
        }
    }
};
