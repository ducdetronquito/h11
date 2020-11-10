const Allocator = std.mem.Allocator;
const BodyReader = @import("readers.zig").BodyReader;
const ClientSM = @import("state_machines/client.zig").ClientSM;
const Event = @import("events.zig").Event;
const Method = @import("http").Method;
const Response = @import("events.zig").Response;
const ServerSM = @import("state_machines/server.zig").ServerSM;
const SMError = @import("state_machines/errors.zig").SMError;
const std = @import("std");


pub const Client = struct {
    localState: ClientSM,
    remoteState: ServerSM,
    sentRequestMethod: ?Method,

    const Error = SMError;

    pub fn init(allocator: *Allocator) Client {
        var localState = ClientSM.init(allocator);
        var remoteState = ServerSM.init(allocator);

        return Client {
            .localState = localState,
            .remoteState = remoteState,
            .sentRequestMethod = null,
        };
    }

    pub fn deinit(self: *Client) void {
        self.localState.deinit();
        self.remoteState.deinit();
        self.sentRequestMethod = null;
    }

    pub fn getResponseBuffer(self: *Client) []const u8 {
        return self.remoteState.getResponseBuffer();
    }

    pub fn send(self: *Client, event: Event) Error![]const u8 {
        var bytes = try self.localState.send(event);
        switch(event) {
            .Request => |request| self.sentRequestMethod = request.method,
            else => {}
        }
        return bytes;
    }

    pub fn receive(self: *Client, data: []const u8) !void {
        try self.remoteState.receive(data);
    }

    pub fn nextEvent(self: *Client) Error!Event {
        var event = try self.remoteState.nextEvent();

        switch (event) {
            .Response => |response| {
                errdefer response.deinit();
                try self.frameResponseBody(response);
            },
            else => {},
        }
        return event;
    }

    // Cf: RFC 7230 - 3.3 Message Boddy
    // https://tools.ietf.org/html/rfc7230#section-3.3
    // https://tools.ietf.org/html/rfc7230#section-3.3.3
    pub fn frameResponseBody(self: *Client, response: Response) Error!void {
        var reader = try BodyReader.frame(self.sentRequestMethod.?, response);
        self.remoteState.defineBodyReader(reader);
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;
const Headers = @import("http").Headers;
const Request = @import("events.zig").Request;


test "Send - Client can send an event" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    client.localState.state = .SendBody;

    var result = try client.send(.EndOfMessage);
}

test "Send - Remember the request method when sending a request event" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    _ = try headers.append("Host", "www.ziglang.org");

    var request = try Request.init(.Get, "/", .Http11, headers);
    var bytes = try client.send(Event {.Request = request });
    std.testing.allocator.free(bytes);

    expect(client.sentRequestMethod.? == .Get);
}

test "NextEvent" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var event = client.nextEvent();
    expectError(error.NeedData, event);
}

test "NextEvent - Fail to return a Response event when the content length is invalid." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();
    client.sentRequestMethod = .Get;

    try client.receive("HTTP/1.1 200 OK\r\nContent-Length: XXX\r\n\r\n");
    var event = client.nextEvent();

    expectError(error.RemoteProtocolError, event);
}

test "NextEvent - A Response event with no content length must be followed by an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();
    client.sentRequestMethod = .Get;

    try client.receive("HTTP/1.1 200 OK\r\n\r\n");
    var event = try client.nextEvent();
    event.deinit();

   event = try client.nextEvent();
   expect(event == .EndOfMessage);
}

test "NextEvent - A Response event with a content length muste be followed by a Data event and an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();
    client.sentRequestMethod = .Get;
    try client.receive("HTTP/1.1 200 OK\r\nContent-Length: 34\r\n\r\nAin't no sunshine when she's gone.");

    var event = try client.nextEvent();
    expect(event.isResponse());
    event.deinit();

    event = try client.nextEvent();
    switch(event) {
        .Data => |data| expect(std.mem.eql(u8, data.content,"Ain't no sunshine when she's gone.")),
        else => unreachable
    }

    event = try client.nextEvent();
    expect(event.isEndOfMessage());
}
