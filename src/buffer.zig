const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocationError = @import("errors.zig").AllocationError;
const ArrayList = std.ArrayList;
const Stream = @import("stream.zig").Stream;


pub const Buffer = struct {
    allocator: *Allocator,
    cursor: usize,
    data: ArrayList(u8),

    pub fn init(allocator: *Allocator) Buffer {
        var data = ArrayList(u8).init(allocator);
        return Buffer{ .allocator = allocator, .cursor = 0, .data = data };
    }

    pub fn deinit(self: *Buffer) void {
        self.data.deinit();
    }

    /// The caller owns the returned memory. Buffer becomes empty.
    pub fn toOwnedSlice(self: *Buffer) []const u8 {
        const result = self.data.toOwnedSlice();
        self.* = init(self.allocator);
        return result;
    }

    pub fn append(self: *Buffer, slice: []const u8) AllocationError!void {
        try self.data.appendSlice(slice);
    }

    pub fn toStream(self: *Buffer) Stream {
        return Stream.init(self.data.items[self.cursor..]);
    }

    pub fn move(self: *Buffer, offset: usize) void {
        self.cursor += offset;
    }
};
