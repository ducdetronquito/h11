const std = @import("std");
const h11 = @import("h11");

const testing = std.testing;

test "Read server response" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = h11.Connection.init(allocator);
    defer connection.deinit();
    var responseData = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 51\r\nContent-Type: text/plain\r\n\r\nHello World! My payload includes a trailing CRLF.\r\n";
    try connection.receiveData(responseData);

    const responseEvent = try connection.nextEvent();

    testing.expect(responseEvent.Response.statusCode == 200);
    testing.expect(std.mem.eql(u8, responseEvent.Response.reason, "OK"));
    const server = responseEvent.Response.headers.get("Server").?.value;
    const contentLenght = responseEvent.Response.headers.get("Content-Length").?.value;
    const contentType = responseEvent.Response.headers.get("Content-Type").?.value;
    testing.expect(std.mem.eql(u8, server, "Apache"));
    testing.expect(std.mem.eql(u8, contentLenght, "51"));
    testing.expect(std.mem.eql(u8, contentType, "text/plain"));

    const dataEvent = try connection.nextEvent();
    testing.expect(std.mem.eql(u8, dataEvent.Data.body, "Hello World! My payload includes a trailing CRLF.\r\n"));

    const endOfMessageEvent = try connection.nextEvent();
    testing.expect(h11.EventTag(endOfMessageEvent) == h11.EventTag.EndOfMessage);
}

test "Read server response - No Content-Length header defaults to 0" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = h11.Connection.init(allocator);
    defer connection.deinit();
    var responseData = "HTTP/1.1 200 OK\r\n\r\n";
    try connection.receiveData(responseData);

    const responseEvent = try connection.nextEvent();

    testing.expect(responseEvent.Response.statusCode == 200);
    testing.expect(std.mem.eql(u8, responseEvent.Response.reason, "OK"));

    const endOfMessageEvent = try connection.nextEvent();
    testing.expect(h11.EventTag(endOfMessageEvent) == h11.EventTag.EndOfMessage);
}
