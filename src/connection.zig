const Allocator = std.mem.Allocator;
const ClientSM = @import("state_machines/client.zig").ClientSM;
const Event = @import("events/events.zig").Event;
const ServerSM = @import("state_machines/server.zig").ServerSM;
const SMError = @import("state_machines/errors.zig").SMError;
const std = @import("std");

pub fn Client(comptime Reader: type, comptime Writer: type) type {
    return struct {
        const Self = @This();
        localState: ClientSM(Writer),
        remoteState: ServerSM(Reader),

        pub fn init(allocator: Allocator, reader: Reader, writer: Writer) Self {
            var localState = ClientSM(Writer).init(allocator, writer);
            var remoteState = ServerSM(Reader).init(allocator, reader);

            return Self{
                .localState = localState,
                .remoteState = remoteState,
            };
        }

        pub fn deinit(self: *Self) void {
            self.localState.deinit();
            self.remoteState.deinit();
        }

        pub fn send(self: *Self, event: Event) !void {
            try self.localState.send(event);
            self.remoteState.expectEvent(event);
        }

        pub fn nextEvent(self: *Self, options: anytype) !Event {
            return self.remoteState.nextEvent(options);
        }
    };
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const Request = @import("events/events.zig").Request;
const TestClient = Client(std.io.FixedBufferStream([]const u8).Reader, std.io.FixedBufferStream([]u8).Writer);

test "Send - Client can send an event" {
    var read_buffer = "";
    var fixed_read_buffer = std.io.fixedBufferStream(read_buffer);
    var write_buffer: [100]u8 = undefined;
    var fixed_write_buffer = std.io.fixedBufferStream(&write_buffer);
    var client = TestClient.init(std.testing.allocator, fixed_read_buffer.reader(), fixed_write_buffer.writer());
    defer client.deinit();

    client.localState.state = .SendBody;
    try client.send(.EndOfMessage);
    try expect(std.mem.startsWith(u8, &write_buffer, ""));
}

test "Send - Remember the request method when sending a request event" {
    var read_buffer = "";
    var fixed_read_buffer = std.io.fixedBufferStream(read_buffer);
    var write_buffer: [100]u8 = undefined;
    var fixed_write_buffer = std.io.fixedBufferStream(&write_buffer);
    var client = TestClient.init(std.testing.allocator, fixed_read_buffer.reader(), fixed_write_buffer.writer());
    defer client.deinit();

    var request = Request.default(std.testing.allocator);
    try client.send(Event{ .Request = request });

    try expect(client.remoteState.expected_request.?.method == .Get);
}

test "NextEvent - A Response event with a content length muste be followed by a Data event and an EndOfMessage event." {
    var content = "HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.";
    var fixed_read_buffer = std.io.fixedBufferStream(content);
    var write_buffer: [100]u8 = undefined;
    var fixed_write_buffer = std.io.fixedBufferStream(&write_buffer);
    var client = TestClient.init(std.testing.allocator, fixed_read_buffer.reader(), fixed_write_buffer.writer());

    var request = Request.default(std.testing.allocator);
    try client.send(Event{ .Request = request });

    var event = try client.nextEvent(.{});
    try expect(event == .Response);
    var response = event.Response;
    defer response.deinit();

    var buffer: [100]u8 = undefined;
    event = try client.nextEvent(.{ .buffer = &buffer });
    try expect(event == .Data);
    var data = event.Data;

    event = try client.nextEvent(.{ .buffer = &buffer });
    try expect(event == .EndOfMessage);

    client.deinit();

    try expect(response.statusCode == .Ok);
    try expect(response.version == .Http11);
    try expect(response.headers.len() == 1);
    try expectEqualStrings(response.headers.items()[0].name.raw(), "Content-Length");
    try expectEqualStrings(response.headers.items()[0].value, "34");
    try expectEqualStrings(data.bytes, "Ain't no sunshine when she's gone.");
}
