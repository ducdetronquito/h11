const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const ClientAutomaton = @import("automatons/client.zig").ClientAutomaton;
const Event = @import("automatons/events.zig").Event;
const HeaderField = @import("automatons/parsers/headers.zig").HeaderField;
const ServerAutomaton = @import("automatons/server.zig").ServerAutomaton;

pub const ConnectionError = error{OutOfMemory};

pub const Connection = struct {
    allocator: *Allocator,
    buffer: Buffer,
    server: ServerAutomaton,
    client: ClientAutomaton,

    pub fn init(allocator: *Allocator) Connection {
        var buffer = Buffer.init(allocator);
        var client = ClientAutomaton.init(allocator);
        var server = ServerAutomaton.init(allocator);
        return Connection{ .allocator = allocator, .buffer = buffer, .client = client, .server = server };
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
    }

    pub fn send(self: *Connection, event: Event) ![]const u8 {
        return self.client.send(event);
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
