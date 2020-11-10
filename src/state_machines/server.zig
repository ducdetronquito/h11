const Allocator = std.mem.Allocator;
const BodyReader = @import("../readers.zig").BodyReader;
const Buffer = @import("../buffer.zig").Buffer;
const ContentLengthReader = @import("../readers.zig").ContentLengthReader;
const Data = @import("../events.zig").Data;
const events = @import("../events.zig");
const Event = events.Event;
const Method = @import("http").Method;
const Response = @import("../events.zig").Response;
const SMError = @import("errors.zig").SMError;
const State = @import("states.zig").State;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;

pub const ServerSM = struct {
    allocator: *Allocator,
    body_reader: BodyReader,
    response_buffer: Buffer,
    sentRequestMethod: ?Method,
    state: State,

    pub fn init(allocator: *Allocator) ServerSM {
        return ServerSM {
            .allocator = allocator,
            .body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) },
            .response_buffer = Buffer.init(allocator),
            .sentRequestMethod = null,
            .state = State.Idle,
        };
    }

    pub fn deinit(self: *ServerSM) void {
        self.state = State.Idle;
        self.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) };
        self.response_buffer.deinit();
    }

    pub fn getResponseBuffer(self: *ServerSM) []const u8 {
        return self.response_buffer.toOwnedSlice();
    }

    pub fn receive(self: *ServerSM, data: []const u8) !void {
        try self.response_buffer.appendSlice(data);
    }

    pub fn nextEvent(self: *ServerSM) SMError!Event {
        return switch(self.state) {
            .Idle => {
                var event = self.readResponse() catch |err| switch(err) {
                    error.NeedData => return err,
                    else => {
                        self.state = .Error;
                        return err;
                    }
                };
                self.state = .SendBody;
                return event;
            },
            .SendBody => {
                var event = self.readData() catch |err| return err;
                if (event == .EndOfMessage) {
                    self.state = .Done;
                }
                return event;
            },
            .Done => {
                self.state = .Closed;
                return .ConnectionClosed;
            },
            .Closed => {
                return .ConnectionClosed;
            },
            else => {
                self.state = .Error;
                return error.RemoteProtocolError;
            }
        };
    }

    fn readData(self: *ServerSM) SMError!Event {
        return try self.body_reader.read(&self.response_buffer);
    }

    fn readResponse(self: *ServerSM) SMError!Event {
        var pos = self.response_buffer.findBlankLine() orelse return error.NeedData;
        var data = self.response_buffer.read(pos + 4) catch return error.NeedData;

        var response = events.Response.parse(self.allocator, data) catch {
            return error.RemoteProtocolError;
        };

        var event = events.Response.init(response.headers, response.statusCode, Version.Http11);
        errdefer event.deinit();

        // Cf: RFC 7230 - 3.3 Message Boddy
        // https://tools.ietf.org/html/rfc7230#section-3.3
        // https://tools.ietf.org/html/rfc7230#section-3.3.3
        self.body_reader = try BodyReader.frame(self.sentRequestMethod.?, response);

        return Event { .Response = event};
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "NextEvent - Can retrieve a Response event when state is Idle" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.sentRequestMethod = .Get;
    try server.receive("HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n");

    var event = try server.nextEvent();

    switch (event) {
        .Response => |response| {
            expect(response.statusCode == .Ok);
            expect(response.version == .Http11);
            response.deinit();
        },
        else => unreachable,
    }
    expect(server.state == .SendBody);
}

test "NextEvent - Ask for more data when not enough is provided to retrieve a Response event" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    try server.receive("HTTP/1.1 200 OK\r\nServer: Apache\r\n");

    var event = server.nextEvent();

    expectError(error.NeedData, event);
    expect(server.state == .Idle);
}

test "NextEvent - Cannot retrieve a response event if the data is invalid" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    try server.receive("INVALID RESPONSE\r\n\r\n");

    var event = server.nextEvent();

    expectError(error.RemoteProtocolError, event);
    expect(server.state == .Error);
}

test "NextEvent - Move into the error state when failing to retrieve a Response event" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    try server.receive("INVALID RESPONSE\r\n\r\n");

    var event = server.nextEvent();

    expect(server.state == .Error);
}

test "NextEvent - Retrieve a Data event when state is SendBody." {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.state = .SendBody;
    server.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(34) };
    try server.receive("Ain't no sunshine when she's gone.");

    var dataEvent = try server.nextEvent();

    switch (dataEvent) {
        .Data => |data| {
            expect(std.mem.eql(u8, data.content, "Ain't no sunshine when she's gone."));
        },
        else => unreachable,
    }
}

test "NextEvent - Retrieving an EndOfMessage event move the state to Done." {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.state = .SendBody;
    server.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) };

    var event = try server.nextEvent();

    expect(event.isEndOfMessage());
    expect(server.state == .Done);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Done" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.state = .Done;

    var event = try server.nextEvent();

    expect(event.isConnectionClosed());
    expect(server.state == .Closed);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Closed" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.state = .Closed;

    var event = try server.nextEvent();

    expect(event.isConnectionClosed());
    expect(server.state == .Closed);
}
