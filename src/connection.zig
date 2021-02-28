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

    pub fn nextEvent(self: *Client, reader: anytype, options: anytype) !Event {
        return self.remoteState.nextEvent(reader, options);
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

test "NextEvent - A Response event with a content length muste be followed by a Data event and an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var request = Request.default(std.testing.allocator);
    var bytes = try client.send(Event{ .Request = request });
    std.testing.allocator.free(bytes);

    const content = "HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.";
    var reader = std.io.fixedBufferStream(content).reader();

    var event = try client.nextEvent(reader, .{});
    expect(event == .Response);
    var response = event.Response;
    defer response.deinit();

    var buffer: [100]u8 = undefined;
    event = try client.nextEvent(reader, .{ .buffer = &buffer });
    expect(event == .Data);
    var data = event.Data;

    event = try client.nextEvent(reader, .{ .buffer = &buffer });
    expect(event == .EndOfMessage);

    client.deinit();

    expect(response.statusCode == .Ok);
    expect(response.version == .Http11);
    expect(response.headers.len() == 1);
    expect(std.mem.eql(u8, response.headers.items()[0].name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, response.headers.items()[0].value, "34"));
    expect(std.mem.eql(u8, data.bytes, "Ain't no sunshine when she's gone."));
}
