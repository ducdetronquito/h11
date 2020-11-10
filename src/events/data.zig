const Allocator = @import("std").mem.Allocator;

pub const Data = struct {
    allocator: ?*Allocator,
    content: []const u8,

    pub fn deinit(self: Data) void {
        if (self.allocator != null) {
            self.allocator.?.free(self.content);
        }
    }
};
