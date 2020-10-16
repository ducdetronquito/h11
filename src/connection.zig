const Allocator = std.mem.Allocator;
const BodyReader = @import("readers.zig").BodyReader;
const Buffer = @import("buffer.zig").Buffer;
pub const ClientSM = @import("state_machines/client.zig").ClientSM;
const ContentLengthReader = @import("readers.zig").ContentLengthReader;
const Event = @import("events.zig").Event;
const Response = @import("events.zig").Response;
pub const ServerSM = @import("state_machines/server.zig").ServerSM;
pub const SMError = @import("state_machines/errors.zig").SMError;
const std = @import("std");


pub const Client = struct {
    buffer: Buffer,
    localState: ClientSM,
    remoteState: ServerSM,

    pub fn init(allocator: *Allocator) Client {
        var localState = ClientSM.init(allocator);
        var remoteState = ServerSM.init(allocator);

        return Client {
            .buffer = Buffer.init(allocator),
            .localState = localState,
            .remoteState = remoteState,
        };
    }

    pub fn deinit(self: *Client) void {
        self.buffer.deinit();
    }

    pub fn send(self: *Client, event: Event) SMError![]const u8 {
        return self.localState.send(event);
    }

    pub fn receive(self: *Client, data: []const u8) !void{
        try self.buffer.appendSlice(data);
    }

    pub fn nextEvent(self: *Client) SMError!Event {
        var event = try self.remoteState.nextEvent(&self.buffer);

        switch (event) {
            .Response => |response| {
                self.frameResponseBody(response) catch |err| {
                    response.deinit();
                    return err;
                };
            },
            else => {},
        }
        return event;
    }

    // Cf: RFC 7230 - 3.3 Message Boddy
    // https://tools.ietf.org/html/rfc7230#section-3.3
    // https://tools.ietf.org/html/rfc7230#section-3.3.3
    pub fn frameResponseBody(self: *Client, response: Response) SMError!void {
        var contentLength: usize = 0;
        var rawContentLength = response.headers.getValue("Content-Length");
        if (rawContentLength != null) {
            contentLength = std.fmt.parseInt(usize, rawContentLength.?, 10) catch return error.RemoteProtocolError;
        }
        var reader = BodyReader { .ContentLength = ContentLengthReader.init(contentLength) };
        self.remoteState.defineBodyReader(reader);
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Send - Client can send an event" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    client.localState.state = .SendBody;

    var result = try client.send(.EndOfMessage);
}


test "Receive" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var incoming_data = "Another one bytes the dust !";
    try client.receive(incoming_data);

    expect(std.mem.eql(u8, client.buffer.toSlice(), incoming_data));
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

    try client.receive("HTTP/1.1 200 OK\r\nContent-Length: XXX\r\n\r\n");
    var event = client.nextEvent();

    expectError(error.RemoteProtocolError, event);
}

test "NextEvent - A Response event with no content length must be followed by an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    try client.receive("HTTP/1.1 200 OK\r\n\r\n");
    var event = try client.nextEvent();
    event.deinit();

   event = try client.nextEvent();
   expect(event == .EndOfMessage);
}

test "NextEvent - A Response event with a content length muste be followed by a Data event and an EndOfMessage event." {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();
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
