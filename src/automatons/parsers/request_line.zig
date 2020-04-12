const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const RequestLine = struct {
    pub fn serialize(buffer: *ArrayList(u8), method: []const u8, target: []const u8) !void {
        try buffer.appendSlice(method);
        try buffer.append(' ');
        try buffer.appendSlice(target);
        try buffer.appendSlice(" HTTP/1.1\r\n");
    }
};

const testing = std.testing;

test "Serialize" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try RequestLine.serialize(&buffer, "GET", "/xml");

    testing.expect(std.mem.eql(u8, buffer.toSliceConst(), "GET /xml HTTP/1.1\r\n"));
}
