const std = @import("std");
const ByteStream = @import("../streams.zig").ByteStream;
const Headers = @import("headers.zig").Headers;
const ParserError = @import("errors.zig").ParserError;


pub const Body = struct {
    pub fn parse(stream: *ByteStream, headers: *Headers) ![]const u8 {
        const rawContentLength = headers.get("Content-Length") catch return "";
        const contentLength = std.fmt.parseInt(usize, rawContentLength, 10) catch unreachable;

        var streamSize = stream.len();
        if (streamSize < contentLength) {
            return ParserError.NeedData;
        }
        if (streamSize > contentLength) {
            return ParserError.BadFormat;
        }

        return stream.read(contentLength);
    }
};


const testing = std.testing;

test "Parse - Success" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var headersStream = ByteStream.init("Content-Length: 12\r\n\r\n");
    var headers = try Headers.parse(allocator, &headersStream);

    var bodyStream = ByteStream.init("Hello World!");
    var body = try Body.parse(&bodyStream, &headers);
    testing.expect(std.mem.eql(u8, body, "Hello World!"));
}

test "Parse - When body is not completely received - Returns NeedData" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var headersStream = ByteStream.init("Content-Length: 666\r\n\r\n");
    var headers = try Headers.parse(allocator, &headersStream);

    var bodyStream = ByteStream.init("Hello World!");
    var body = Body.parse(&bodyStream, &headers);
    testing.expectError(ParserError.NeedData, body);
}

test "Parse - Bigger body than expected - Returns BadFormat" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var headersStream = ByteStream.init("Content-Length: 10\r\n\r\n");
    var headers = try Headers.parse(allocator, &headersStream);

    var bodyStream = ByteStream.init("Hello World!");
    var body = Body.parse(&bodyStream, &headers);
    testing.expectError(ParserError.BadFormat, body);
}

