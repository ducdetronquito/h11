const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Headers = @import("headers.zig").Headers;
const ParserError = @import("errors.zig").ParserError;


pub const Body = struct {
    pub fn parse(buffer: *Buffer, headers: *Headers) ![]const u8 {
        const rawContentLength = headers.get("Content-Length") catch return "";
        const contentLength = std.fmt.parseInt(usize, rawContentLength, 10) catch unreachable;

        var bufferSize = buffer.len();
        if (bufferSize < contentLength) {
            return ParserError.NeedData;
        }
        if (bufferSize > contentLength) {
            return ParserError.BadFormat;
        }

        return buffer.read(contentLength);
    }
};


const testing = std.testing;

test "Parse - When body is not completely received - Returns NeedData" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headersBuffer = Buffer.init(allocator);
    try headersBuffer.append("Content-Length: 666\r\n\r\n");
    var headers = try Headers.parse(allocator, &headersBuffer);

    var bodyBuffer = Buffer.init(allocator);
    try bodyBuffer.append("Hello World!");
    var body = Body.parse(&bodyBuffer, &headers);

    testing.expectError(ParserError.NeedData, body);
}

test "Parse - Bigger body than expected - Returns BadFormat" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headersBuffer = Buffer.init(allocator);
    try headersBuffer.append("Content-Length: 10\r\n\r\n");
    var headers = try Headers.parse(allocator, &headersBuffer);

    var bodyBuffer = Buffer.init(allocator);
    try bodyBuffer.append("Hello World!");
    var body = Body.parse(&bodyBuffer, &headers);

    testing.expectError(ParserError.BadFormat, body);
}

test "Parse - Success" {
    var memory: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&memory).allocator;

    var headersBuffer = Buffer.init(allocator);
    try headersBuffer.append("Content-Length: 12\r\n\r\n");
    var headers = try Headers.parse(allocator, &headersBuffer);

    var bodyBuffer = Buffer.init(allocator);
    try bodyBuffer.append("Hello World!");
    var body = try Body.parse(&bodyBuffer, &headers);
    testing.expect(std.mem.eql(u8, body, "Hello World!"));
}
