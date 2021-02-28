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
    expected_request: ?Request,
    state: State,
    body_buffer: [4096]u8 = undefined,
    body_buffer_length: usize = 0,

    pub fn init(allocator: *Allocator) ServerSM {
        return ServerSM{
            .allocator = allocator,
            .body_reader = BodyReader.default(),
            .expected_request = null,
            .state = State.Idle,
        };
    }

    pub fn deinit(self: *ServerSM) void {
        self.body_reader = BodyReader.default();
        self.expected_request = null;
        self.state = State.Idle;
    }

    pub fn expectEvent(self: *ServerSM, event: Event) void {
        switch (event) {
            .Request => |request| {
                self.expected_request = request;
            },
            else => {},
        }
    }

    pub fn nextEvent(self: *ServerSM, reader: anytype, options: anytype) !Event {
        return switch (self.state) {
            .Idle => {
                var event = self.readResponse(reader) catch |err| {
                    self.state = .Error;
                    return err;
                };
                self.state = .SendBody;
                return event;
            },
            .SendBody => {
                var event = self.readData(reader, options) catch |err| return err;
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
            },
        };
    }

    fn readResponse(self: *ServerSM, reader: anytype) !Event {
        var raw_response = try self.readRawResponse(reader);

        var response = Response.parse(self.allocator, raw_response) catch |err| {
            self.allocator.free(raw_response);
            return err;
        };
        errdefer response.deinit();

        self.body_reader = try BodyReader.frame(self.expected_request.?.method, response.statusCode, response.headers);

        return Event{ .Response = response };
    }

    fn readRawResponse(self: *ServerSM, reader: anytype) ![]u8 {
        var response_buffer = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        errdefer response_buffer.deinit();

        var last_3_chars: [3]u8 = undefined;
        while (true) {
            var buffer: [4096]u8 = undefined;
            const count = try reader.read(&buffer);
            var bytes = buffer[0..count];

            if (count == 0 or response_buffer.items.len + bytes.len > 64_000) {
                return error.ResponseTooLarge;
            }

            if (last_3_chars[0] == '\r' and last_3_chars[1] == '\n' and last_3_chars[2] == '\r' and bytes[0] == '\n') {
                var body = bytes[1..];
                std.mem.copy(u8, &self.body_buffer, body);
                self.body_buffer_length = body.len;
                try response_buffer.append('\n');
                break;
            } else if (last_3_chars[1] == '\r' and last_3_chars[2] == '\n' and bytes[0] == '\r' and bytes[1] == '\n') {
                var body = bytes[2..];
                std.mem.copy(u8, &self.body_buffer, body);
                self.body_buffer_length = body.len;
                try response_buffer.appendSlice("\r\n");
                break;
            } else if (last_3_chars[2] == '\r' and bytes[0] == '\n' and bytes[1] == '\r' and bytes[2] == '\n') {
                var body = bytes[3..];
                std.mem.copy(u8, &self.body_buffer, body);
                self.body_buffer_length = body.len;
                try response_buffer.appendSlice("\n\r\n");
                break;
            }

            var end_of_response = std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse {
                std.mem.copy(u8, &last_3_chars, bytes[bytes.len-3..]);
                try response_buffer.appendSlice(bytes);
                continue;
            };

            try response_buffer.appendSlice(bytes[0..end_of_response + 4]);
            if (end_of_response != bytes.len - 4) {
                var body = bytes[end_of_response + 4..];
                std.mem.copy(u8, &self.body_buffer, body);
                self.body_buffer_length = body.len;
            }
            break;
        }

        return response_buffer.toOwnedSlice();
    }

    fn readData(self: *ServerSM, reader: anytype, options: anytype) !Event {
        if (!@hasField(@TypeOf(options), "buffer")) {
            @panic("You must provide a buffer to read into.");
        }
        if (self.body_buffer_length > 0) {
            var fixed_stream = std.io.fixedBufferStream(self.body_buffer[0..self.body_buffer_length]);
            // TODO: Deal when the options.buffer cannot read all data in self.body_buffer at once.
            return try self.body_reader.read(fixed_stream.reader(), options.buffer);
        }
        return try self.body_reader.read(reader, options.buffer);
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
    server.expectEvent(Event{ .Request = request });


    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var event = try server.nextEvent(reader, .{});
    expect(event.Response.statusCode == .Ok);
    expect(event.Response.version == .Http11);
    expect(server.state == .SendBody);
    event.Response.deinit();

    var buffer: [100]u8 = undefined;
    event = try server.nextEvent(reader, .{ .buffer = &buffer });
    expect(event == .EndOfMessage);
}

test "NextEvent - Can retrieve a Response and Data when state is Idle" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 14\r\n\r\nGotta go fast!";
    var toto = std.io.fixedBufferStream(content);
    var reader = toto.reader();

    var event = try server.nextEvent(reader, .{});
    expect(event.Response.statusCode == .Ok);
    expect(event.Response.version == .Http11);
    expect(server.state == .SendBody);
    event.Response.deinit();

    var buffer: [100]u8 = undefined;
    event = try server.nextEvent(reader, .{ .buffer = &buffer });
    expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!"));
    expect(std.mem.eql(u8, buffer[0..14], "Gotta go fast!"));
    expect(server.state == .SendBody);

    event = try server.nextEvent(reader, .{ .buffer = &buffer});
    expect(event == .EndOfMessage);
    expect(server.state == .Done);
}

test "NextEvent - Read response in various read" {
    var responses = [_][]const u8 {
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nCookie: " ++ "a" ** 4047 ++ "\r\n\r\nGotta go fast!",
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nCookie: " ++ "a" ** 4048 ++ "\r\n\r\nGotta go fast!",
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nCookie: " ++ "a" ** 4049 ++ "\r\n\r\nGotta go fast!",
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nCookie: " ++ "a" ** 4050 ++ "\r\n\r\nGotta go fast!",
    };
    for(responses) |response| {
        var server = ServerSM.init(std.testing.allocator);
        defer server.deinit();

        var request = Request.default(std.testing.allocator);
        defer request.deinit();
        server.expectEvent(Event{ .Request = request });

        var toto = std.io.fixedBufferStream(response);
        var reader = toto.reader();

        var event = try server.nextEvent(reader, .{});
        event.Response.deinit();

        var buffer: [100]u8 = undefined;
        event = try server.nextEvent(reader, .{ .buffer = &buffer});
        expect(std.mem.eql(u8, event.Data.bytes, "Gotta go fast!"));
    }
}

test "NextEvent - When the response size is above the limit - Returns ResponseTooLarge" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    const content = "HTTP/1.1 200 OK\r\nCookie: " ++ "a" ** 65_000 ++ "\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    const failure = server.nextEvent(reader, .{});

    expectError(error.ResponseTooLarge, failure);
}

test "NextEvent - When fail to read from the reader - Returns reader' error" {
    const FailingReader = struct {
        const Self = @This();
        const ReadError = error { Failed };
        const Reader = std.io.Reader(*Self, ReadError, read);   

        fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *Self, buffer: []u8) ReadError!usize {
            return error.Failed;
        }
    };

    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    // TODO: Add a test that fails after one allocation
    var reader = FailingReader{};

    const failure = server.nextEvent(reader.reader(), .{});

    expectError(error.Failed, failure);
}

test "NextEvent - Cannot retrieve a response event if the data is invalid" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    const content = "INVALID RESPONSE\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();

    var event = server.nextEvent(reader, .{});

    expectError(error.Invalid, event);
    expect(server.state == .Error);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Done" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.state = .Done;

    var reader = std.io.fixedBufferStream("").reader();
    var event = try server.nextEvent(reader, .{});

    expect(event.isConnectionClosed());
    expect(server.state == .Closed);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Closed" {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();
    server.state = .Closed;

    var reader = std.io.fixedBufferStream("").reader();
    var event = try server.nextEvent(reader, .{});

    expect(event.isConnectionClosed());
    expect(server.state == .Closed);
}

test "NextEvent - Fail to return a Response event when the content length is invalid." {
    var server = ServerSM.init(std.testing.allocator);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    var content = "HTTP/1.1 200 OK\r\nContent-Length: XXX\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var failure = server.nextEvent(reader, .{});

    expectError(error.RemoteProtocolError, failure);
}
