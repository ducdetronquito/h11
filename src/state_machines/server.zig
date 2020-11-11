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
    body_buffer: Buffer,
    response_buffer: Buffer,
    sentRequestMethod: ?Method,
    state: State,

    pub fn init(allocator: *Allocator) ServerSM {
        return ServerSM {
            .allocator = allocator,
            .body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) },
            .body_buffer = Buffer.init(allocator),
            .response_buffer = Buffer.init(allocator),
            .sentRequestMethod = null,
            .state = State.Idle,
        };
    }

    pub fn deinit(self: *ServerSM) void {
        self.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) };
        self.body_buffer.deinit();
        self.response_buffer.deinit();
        self.state = State.Idle;
    }

    pub fn receive(self: *ServerSM, data: []const u8) !void {
        if (self.state != .Idle) {
            return try self.body_buffer.appendSlice(data);
        }

        var response = self.readUntilBlankLine(data);
        if (response) |value|{
            try self.response_buffer.appendSlice(value);
            var body = data[value.len..];
            try self.body_buffer.appendSlice(body);
        } else {
            try self.response_buffer.appendSlice(data);
        }
    }

    fn readUntilBlankLine(self: ServerSM, data: []const u8) ?[]const u8 {
        var i: usize = 0;
        while(i < data.len) {
            if (data[i] != '\r') {
                i += 1;
                continue;
            }

            if (data.len - i < 4) {
                return null;
            }

            i += 4;
            if (std.mem.eql(u8, data[i-3..i], "\n\r\n")) {
                return data[0..i];
            }
        }

        return null;
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
        var event = try self.body_reader.read(&self.body_buffer);
        switch(event) {
            .Data => |*data| {
                data.content = self.body_buffer.toOwnedSlice();
            },
            else => {},
        }
        return event;
    }

    fn readResponse(self: *ServerSM) SMError!Event {
        var data = self.response_buffer.toSlice();
        if (data.len < 4 or !std.mem.eql(u8, data[data.len-4..], "\r\n\r\n")) {
            return error.NeedData;
        }

        var response = events.Response.parse(self.allocator, data) catch {
            return error.RemoteProtocolError;
        };
        errdefer response.headers.deinit();

        // Cf: RFC 7230 - 3.3 Message Boddy
        // https://tools.ietf.org/html/rfc7230#section-3.3
        // https://tools.ietf.org/html/rfc7230#section-3.3.3
        self.body_reader = try BodyReader.frame(self.sentRequestMethod.?, response.statusCode, response.headers);

        response.raw_bytes = self.response_buffer.toOwnedSlice();
        return Event { .Response = response};
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

test "NextEvent - Can retrieve a Response event when state is Idle with the payload" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.sentRequestMethod = .Get;
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
    server.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(34) };
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

test "NextEvent - Fail to return a Response event when the content length is invalid." {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.sentRequestMethod = .Get;

    try server.receive("HTTP/1.1 200 OK\r\nContent-Length: XXX\r\n\r\n");
    var event = server.nextEvent();

    expectError(error.RemoteProtocolError, event);
}
