const Allocator = std.mem.Allocator;
const std = @import("std");


pub const ServerSM = struct {
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) ServerSM {
        return ServerSM { .allocator = allocator };
    }
};
