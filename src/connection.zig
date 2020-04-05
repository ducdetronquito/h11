const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const Event = @import("automatons.zig").Event;
const EventTag = @import("automatons.zig").EventTag;
const ServerAutomaton = @import("automatons.zig").ServerAutomaton;


pub const ConnectionError = error {
    OutOfMemory,
};


pub const Connection = struct {
    allocator: *Allocator,
    buffer: Buffer,
    server: ServerAutomaton,

    pub fn init(allocator: *Allocator) Connection {
        var buffer = Buffer.init(allocator);
        var server = ServerAutomaton.init(allocator);
        return Connection{ .allocator = allocator, .buffer = buffer, .server = server };
    }

    pub fn deinit(self: *Connection) void {
        self.buffer.deinit();
    }

    /// Add data to the connection internal buffer.
    pub fn receiveData(self: *Connection, data: []const u8) !void {
        try self.buffer.append(data);
    }

    pub fn nextEvent(self: *Connection) !Event {
        return self.server.nextEvent(&self.buffer);
        // var body = try Body.parse(&self.buffer, contentLength);
    }
};


const testing = std.testing;

test "Init and deinit" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = Connection.init(allocator);
    defer connection.deinit();
}

test "Receive data" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = Connection.init(allocator);
    defer connection.deinit();

    var data = "Hello";
    try connection.receiveData(data);
}

test "Receive data - Out of memory" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = Connection.init(allocator);
    defer connection.deinit();

    var data = "Hello World!";
    testing.expectError(error.OutOfMemory, connection.receiveData(data));
}


test "Read server response" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = Connection.init(allocator);
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
}
