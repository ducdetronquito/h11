const std = @import("std");
const Buffer = @import("../../buffer.zig").Buffer;
const EventError = @import("../errors.zig").EventError;


pub const Body = struct {
    pub fn parse(buffer: *Buffer, contentLength: usize) ![]const u8 {
        var bufferSize = buffer.len();
        if (bufferSize < contentLength) {
            return EventError.NeedData;
        }
        if (bufferSize > contentLength) {
            return EventError.RemoteProtocolError;
        }

        return buffer.read(contentLength);
    }
};


const testing = std.testing;

test "Parse - When body is not completely received - Returns NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var bodyBuffer = Buffer.init(allocator);
    try bodyBuffer.append("Hello World!");
    var body = Body.parse(&bodyBuffer, 666);

    testing.expectError(EventError.NeedData, body);
}

test "Parse - Bigger body than expected - Returns RemoteProtocolError" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var bodyBuffer = Buffer.init(allocator);
    try bodyBuffer.append("Hello World!");
    var body = Body.parse(&bodyBuffer, 10);

    testing.expectError(EventError.RemoteProtocolError, body);
}

test "Parse - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var bodyBuffer = Buffer.init(allocator);
    try bodyBuffer.append("Hello World!");
    var body = try Body.parse(&bodyBuffer, 12);

    testing.expect(std.mem.eql(u8, body, "Hello World!"));
}
