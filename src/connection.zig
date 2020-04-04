const std = @import("std");
const Allocator = std.mem.Allocator;
const Body = @import("parsers.zig").Body;
const Buffer = @import("buffer.zig").Buffer;
const Headers = @import("parsers.zig").Headers;
const StatusLine = @import("parsers.zig").StatusLine;


pub const ConnectionError = error {
    OutOfMemory,
};


pub const EventError = error {
    NeedData,
    RemoteProtocolError
};


pub const Connection = struct {
    allocator: *Allocator,
    buffer: Buffer,

    pub fn init(allocator: *Allocator) Connection {
        var buffer = Buffer.init(allocator);
        return Connection{ .allocator = allocator, .buffer = buffer };
    }

    pub fn deinit(self: *Connection) void {
        self.buffer.deinit();
    }

    /// Add data to the connection internal buffer.
    pub fn receiveData(self: *Connection, data: []const u8) !void {
        try self.buffer.append(data);
    }

    pub fn nextEvent(self: *Connection) !void {
        var statusLine = try StatusLine.parse(&self.buffer);
        var headers = try Headers.parse(self.allocator, &self.buffer);

        const rawContentLength = headers.get("Content-Length") orelse {
            return EventError.RemoteProtocolError;
        };

        const contentLength = std.fmt.parseInt(usize, rawContentLength.value, 10) catch {
            return EventError.RemoteProtocolError;
        };

        var body = try Body.parse(&self.buffer, contentLength);
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
    var responseData = "HTTP/1.1 200 OK`\r\nServer: Apache\r\nContent-Length: 51\r\nContent-Type: text/plain\r\n\r\nHello World! My payload includes a trailing CRLF.\r\n";
    try connection.receiveData(responseData);

    try connection.nextEvent();
}
