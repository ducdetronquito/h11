const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = std.Buffer;
const StatusLine = @import("parsers/status_line.zig").StatusLine;


pub const ConnectionError = error {
    OutOfMemory,
};


pub const EventError = error {
    NeedData,
    RemoteProtocolError
};


pub const Connection = struct {
    buffer: std.Buffer,

    pub fn init(allocator: *Allocator) !Connection {
        var buffer = Buffer.initSize(allocator, 0) catch |err| switch (err) {
            error.OutOfMemory => { return ConnectionError.OutOfMemory; }
        };
        return Connection { .buffer = buffer };
    }

    pub fn deinit(self: *Connection) void {
        self.buffer.deinit();
    }


    /// Add data to the connection internal buffer.
    pub fn receiveData(self: *Connection, data: []const u8) !void {
        self.buffer.append(data) catch |err| switch (err) {
            error.OutOfMemory => { return ConnectionError.OutOfMemory; }
        };
    }

    pub fn nextEvent(self: *Connection) !void {
        var statusLine = try StatusLine.parse(self.buffer);
    }
};


const testing = std.testing;

test "Init and deinit" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = try Connection.init(allocator);
    defer connection.deinit();
}

test "Init and deinit - Out of memory" {
    var buffer: [1]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    testing.expectError(ConnectionError.OutOfMemory, Connection.init(allocator));
}


test "Receive data" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = try Connection.init(allocator);
    defer connection.deinit();

    var data = "Hello";
    try connection.receiveData(data);
}


test "Receive data - Out of memory" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var connection = try Connection.init(allocator);
    defer connection.deinit();

    var data = "Hello World!";
    testing.expectError(ConnectionError.OutOfMemory, connection.receiveData(data));
}
