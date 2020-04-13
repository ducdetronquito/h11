const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const ClientAutomaton = @import("client.zig").ClientAutomaton;
const Event = @import("events.zig").Event;
const ServerAutomaton = @import("server.zig").ServerAutomaton;

fn Connection(comptime L: type, comptime R: type) type {
    return struct {
        allocator: *Allocator,
        buffer: Buffer,
        localState: L,
        remoteState: R,

        pub fn init(allocator: *Allocator) Connection(L, R) {
            var buffer = Buffer.init(allocator);
            var localState = L.init(allocator);
            var remoteState = R.init(allocator);
            return Connection(L, R){ .allocator = allocator, .buffer = buffer, .localState = localState, .remoteState = remoteState };
        }

        pub fn deinit(self: *Connection(L, R)) void {
            self.buffer.deinit();
        }

        /// Add data to the connection internal buffer.
        pub fn receiveData(self: *Connection(L, R), data: []const u8) !void {
            try self.buffer.append(data);
        }

        pub fn nextEvent(self: *Connection(L, R)) !Event {
            return self.remoteState.nextEvent(&self.buffer);
        }

        pub fn send(self: *Connection(L, R), event: Event) ![]const u8 {
            return self.localState.send(event);
        }
    };
}

pub const Client = Connection(ClientAutomaton, ServerAutomaton);

const testing = std.testing;

test "Init and deinit" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = Client.init(allocator);
    defer client.deinit();
}

test "Receive data" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = Client.init(allocator);
    defer client.deinit();

    var data = "Hello";
    try client.receiveData(data);
}

test "Receive data - Out of memory" {
    var buffer: [10]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = Client.init(allocator);
    defer client.deinit();

    var data = "Hello World!";
    testing.expectError(error.OutOfMemory, client.receiveData(data));
}
