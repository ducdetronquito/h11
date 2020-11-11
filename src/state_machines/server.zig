const Allocator = std.mem.Allocator;
const Buffer = std.ArrayList(u8);
const BodyReader = @import("../readers.zig").BodyReader;
const ContentLengthReader = @import("../readers.zig").ContentLengthReader;
const Data = @import("../events/events.zig").Data;
const Event = @import("../events/events.zig").Event;
const Method = @import("http").Method;
const Request = @import("../events/events.zig").Request;
const Response = @import("../events/events.zig").Response;
const SMError = @import("errors.zig").SMError;
const State = @import("states.zig").State;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const utils = @import("utils.zig");
const Version = @import("http").Version;


pub const ServerSM = struct {
    allocator: *Allocator,
    body_reader: BodyReader,
    body_buffer: Buffer,
    expected_request: ?Request,
    response_buffer: Buffer,
    state: State,

    pub fn init(allocator: *Allocator) ServerSM {
        return ServerSM {
            .allocator = allocator,
            .body_reader = BodyReader.default(),
            .body_buffer = Buffer.init(allocator),
            .expected_request = null,
            .response_buffer = Buffer.init(allocator),
            .state = State.Idle,
        };
    }

    pub fn deinit(self: *ServerSM) void {
        self.body_reader = BodyReader.default();
        self.body_buffer.deinit();
        self.expected_request = null;
        self.response_buffer.deinit();
        self.state = State.Idle;
    }

    pub fn expectEvent(self: *ServerSM, event: Event) void {
        switch(event) {
            .Request => |request| {
                self.expected_request = request;
            },
            else => {},
        }
    }

    pub fn receive(self: *ServerSM, data: []const u8) !void {
        if (self.state != .Idle) {
            return try self.body_buffer.appendSlice(data);
        }

        var response = utils.readUntilBlankLine(data);
        if (response) |value|{
            try self.response_buffer.appendSlice(value);
            var body = data[value.len..];
            try self.body_buffer.appendSlice(body);
        } else {
            try self.response_buffer.appendSlice(data);
        }
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
        return try self.body_reader.read(&self.body_buffer);
    }

    fn readResponse(self: *ServerSM) SMError!Event {
        var data = self.response_buffer.items;
        if (data.len < 4 or !std.mem.eql(u8, data[data.len-4..], "\r\n\r\n")) {
            return error.NeedData;
        }

        var response = Response.parse(self.allocator, data) catch {
            return error.RemoteProtocolError;
        };
        errdefer response.headers.deinit();

        self.body_reader = try BodyReader.frame(self.expected_request.?.method, response.statusCode, response.headers);

        response.raw_bytes = self.response_buffer.toOwnedSlice();
        return Event { .Response = response};
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;
const Headers = @import("http").Headers;

test "NextEvent - Can retrieve a Response event when state is Idle" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event {.Request = request});

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

test "NextEvent - Can retrieve a Response event when state is Idle with the payload" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event {.Request = request});

    try server.receive("HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 14\r\n\r\nGotta go fast!");

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
    server.body_reader = ContentLengthReader.init(34);
    try server.receive("Ain't no sunshine when she's gone.");

    var data_event = try server.nextEvent();
    defer data_event.deinit();
    switch (data_event) {
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
    server.body_reader = BodyReader.default();

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

test "NextEvent - Fail to return a Response event when the content length is invalid." {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event {.Request = request});

    try server.receive("HTTP/1.1 200 OK\r\nContent-Length: XXX\r\n\r\n");
    var event = server.nextEvent();

    expectError(error.RemoteProtocolError, event);
}
