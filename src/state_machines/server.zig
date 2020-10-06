const Allocator = std.mem.Allocator;
const BodyReader = @import("../readers.zig").BodyReader;
const Buffer = @import("../buffer.zig").Buffer;
const ContentLengthReader = @import("../readers.zig").ContentLengthReader;
const Data = @import("../events.zig").Data;
const events = @import("../events.zig");
const Event = events.Event;
const Header = @import("../parsers/main.zig").Header;
const HeaderMap = @import("http").HeaderMap;
const parsers = @import("../parsers/main.zig");
const SMError = @import("errors.zig").SMError;
const State = @import("states.zig").State;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;

pub const ServerSM = struct {
    allocator: *Allocator,
    body_reader: BodyReader,
    state: State,

    pub fn init(allocator: *Allocator) ServerSM {
        return ServerSM {
            .allocator = allocator,
            .body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) },
            .state = State.Idle,
        };
    }

    pub fn defineBodyReader(self: *ServerSM, body_reader: BodyReader) void {
        self.body_reader = body_reader;
    }

    pub fn nextEvent(self: *ServerSM, buffer: *Buffer) SMError!Event {
        return switch(self.state) {
            .Idle => {
                var event = self.readResponse(buffer) catch |err| switch(err) {
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
                var event = self.readData(buffer) catch |err| return err;
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

    fn readData(self: *ServerSM, buffer: *Buffer) SMError!Event {
        return try self.body_reader.read(buffer);
    }

    fn readResponse(self: *ServerSM, buffer: *Buffer) SMError!Event {
        var raw_headers = try self.allocator.alloc(?Header, 128);
        defer self.allocator.free(raw_headers);


        var pos = buffer.findBlankLine() orelse return error.NeedData;
        var data = buffer.read(pos + 4) catch return error.NeedData;

        var raw_response = parsers.Response.parse(data, raw_headers) catch return error.RemoteProtocolError;

        var headers = HeaderMap.init(self.allocator);
        errdefer headers.deinit();
        for (raw_headers) |item| {
            if (item != null) {
                _ = try headers.put(item.?.name, item.?.value);
            }
            break;
        }

        // NB: Should we validate the status code range withun the parsers directly.
        var statusCode = StatusCode.from_u16(raw_response.statusCode) catch |err| return error.RemoteProtocolError;

        var responseEvent = events.Response.init(headers, statusCode, Version.Http11);

        return Event { .Response = responseEvent};
    }
};


const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "NextEvent - Can retrieve a Response event when state is Idle" {
    var server = ServerSM.init(std.testing.allocator);

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n");

    var event = try server.nextEvent(&buffer);
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

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("HTTP/1.1 200 OK\r\nServer: Apache\r\n");

    var event = server.nextEvent(&buffer);
    expectError(error.NeedData, event);
    expect(server.state == .Idle);
}

test "NextEvent - Cannot retrieve a response event if the data is invalid" {
    var server = ServerSM.init(std.testing.allocator);

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("INVALID RESPONSE\r\n\r\n");

    var event = server.nextEvent(&buffer);
    expectError(error.RemoteProtocolError, event);
    expect(server.state == .Error);
}


test "NextEvent - Cannot retrieve a response event if the status code is not valid" {
    var server = ServerSM.init(std.testing.allocator);

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("HTTP/1.1 836 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n");

    var event = server.nextEvent(&buffer);
    expectError(error.RemoteProtocolError, event);
    expect(server.state == .Error);
}

test "NextEvent - Move into the error state when failing to retrieve a Response event" {
    var server = ServerSM.init(std.testing.allocator);

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("INVALID RESPONSE\r\n\r\n");

    var event = server.nextEvent(&buffer);
    expect(server.state == .Error);
}


test "NextEvent - Retrieve a Response event when state is Idle" {
    var server = ServerSM.init(std.testing.allocator);

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n");

    var event = try server.nextEvent(&buffer);
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


test "NextEvent - Retrieve a Data event when state is SendBody." {
    var server = ServerSM.init(std.testing.allocator);
    server.state = .SendBody;
    server.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(34) };

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try buffer.appendSlice("Ain't no sunshine when she's gone.");

    var dataEvent = try server.nextEvent(&buffer);

     switch (dataEvent) {
        .Data => |data| {
            expect(std.mem.eql(u8, data.content, "Ain't no sunshine when she's gone."));
        },
        else => unreachable,
     }
}

test "NextEvent - Retrieving an EndOfMessage event move the state to Done." {
    var server = ServerSM.init(std.testing.allocator);
    server.state = .SendBody;
    server.body_reader = BodyReader { .ContentLength = ContentLengthReader.init(0) };

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    var event = try server.nextEvent(&buffer);
    expect(event.isEndOfMessage());
    expect(server.state == .Done);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Done" {
    var server = ServerSM.init(std.testing.allocator);
    server.state = .Done;

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    var event = try server.nextEvent(&buffer);
    expect(event.isConnectionClosed());
    expect(server.state == .Closed);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Closed" {
    var server = ServerSM.init(std.testing.allocator);
    server.state = .Closed;

    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    var event = try server.nextEvent(&buffer);
    expect(event.isConnectionClosed());
    expect(server.state == .Closed);
}
