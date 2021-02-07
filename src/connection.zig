const Allocator = std.mem.Allocator;
const ClientSM = @import("state_machines/client.zig").ClientSM;
const Event = @import("events/events.zig").Event;
const ServerSM = @import("state_machines/server.zig").ServerSM;
const SMError = @import("state_machines/errors.zig").SMError;
const std = @import("std");

pub const Client = struct {
    localState: ClientSM,
    remoteState: ServerSM,

    const Error = SMError;

    pub fn init(allocator: *Allocator) Client {
        var localState = ClientSM.init(allocator);
        var remoteState = ServerSM.init(allocator);

        return Client{
            .localState = localState,
            .remoteState = remoteState,
        };
    }

    pub fn deinit(self: *Client) void {
        self.localState.deinit();
        self.remoteState.deinit();
    }

    pub fn send(self: *Client, event: Event) Error![]const u8 {
        var bytes = try self.localState.send(event);
        self.remoteState.expectEvent(event);
        return bytes;
    }

    pub fn receive(self: *Client, data: []const u8) !void {
        try self.remoteState.receive(data);
    }

    pub fn nextEvent(self: *Client) Error!Event {
        return self.remoteState.nextEvent();
    }

    pub fn read(self: *Client, reader: anytype, buffer: []u8) !Event {
        return self.remoteState.readFromStream(reader, buffer);
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const Headers = @import("http").Headers;
const Request = @import("events/events.zig").Request;

test "Send - Client can send an event" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    client.localState.state = .SendBody;

    var result = try client.send(.EndOfMessage);
}

test "Send - Remember the request method when sending a request event" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    expect(client.remoteState.expected_request.?.method == .Get);
}

test "NextEvent" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var event = client.nextEvent();
    expectError(error.NeedData, event);
}

test "NextEvent - A Response event with no content length must be followed by an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    try client.receive("HTTP/1.1 200 OK\r\n\r\n");

    var event = try client.nextEvent();
    event.deinit();

    event = try client.nextEvent();
    expect(event == .EndOfMessage);
}

test "NextEvent - A Response event with a content length muste be followed by a Data event and an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    try client.receive("HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.");

    var response_event = try client.nextEvent();
    defer response_event.deinit();
    expect(response_event.isResponse());

    var data_event = try client.nextEvent();
    defer data_event.deinit();
    switch (data_event) {
        .Data => |data| expect(std.mem.eql(u8, data.content, "Ain't no sunshine when she's gone.")),
        else => unreachable,
    }

    var end_of_message_event = try client.nextEvent();
    expect(end_of_message_event.isEndOfMessage());
}

test "Deinit - Response is not invalidated when the client is uninitialized." {
    var client = Client.init(std.testing.allocator);

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    try client.receive("HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.");

    var event = try client.nextEvent();
    var response = switch (event) {
        .Response => |value| value,
        else => unreachable,
    };
    defer response.deinit();

    client.deinit();

    expect(response.statusCode == .Ok);
    expect(response.version == .Http11);
    expect(response.headers.len() == 1);
    expect(std.mem.eql(u8, response.headers.items()[0].name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, response.headers.items()[0].value, "34"));
}

test "Deinit - Response body is not invalidated when the client is uninitialized." {
    var client = Client.init(std.testing.allocator);

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    try client.receive("HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.");

    var response_event = try client.nextEvent();
    response_event.deinit();

    var event = try client.nextEvent();
    var data = switch (event) {
        .Data => |value| value,
        else => unreachable,
    };
    defer data.deinit();

    client.deinit();

    expect(std.mem.eql(u8, data.content, "Ain't no sunshine when she's gone."));
}


test "Read - A Response event with no content length must be followed by an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    try client.receive("HTTP/1.1 200 OK\r\n\r\n");

    var read_buffer: [100]u8 = undefined;
    var content = "HTTP/1.1 200 OK\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var event = try client.read(reader, &read_buffer);
    switch (event) {
        .Response => |*response| {
            response.headers.deinit();
        },
        else => {
            std.debug.panic("Not a response event.", .{});
        }
    }

    event = try client.nextEvent();
    expect(event == .EndOfMessage);
}
