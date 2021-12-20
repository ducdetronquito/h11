const Allocator = std.mem.Allocator;
const Buffer = std.ArrayList(u8);
const BodyReader = @import("../readers/readers.zig").BodyReader;
const Data = @import("../events/events.zig").Data;
const Event = @import("../events/events.zig").Event;
const Method = @import("http").Method;
const Request = @import("../events/events.zig").Request;
const Response = @import("../events/events.zig").Response;
const SMError = @import("errors.zig").SMError;
const State = @import("states.zig").State;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;

const MaximumResponseSize = 64_000;
const ReaderLookahead = 32;

pub fn ServerSM(comptime Reader: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        body_reader: ?BodyReader,
        expected_request: ?Request,
        state: State,
        reader: std.io.PeekStream(.{ .Static = ReaderLookahead }, Reader),

        pub fn init(allocator: Allocator, reader: Reader) Self {
            return .{ .allocator = allocator, .body_reader = null, .expected_request = null, .state = State.Idle, .reader = std.io.peekStream(ReaderLookahead, reader) };
        }

        pub fn deinit(self: *Self) void {
            self.body_reader = null;
            self.expected_request = null;
            self.state = State.Idle;
        }

        pub fn expectEvent(self: *Self, event: Event) void {
            switch (event) {
                .Request => |request| {
                    self.expected_request = request;
                },
                else => {},
            }
        }

        pub fn nextEvent(self: *Self, options: anytype) !Event {
            return switch (self.state) {
                .Idle => {
                    var event = self.readResponse() catch |err| {
                        self.state = .Error;
                        return err;
                    };
                    self.state = .SendBody;
                    return event;
                },
                .SendBody => {
                    var event = self.readData(options) catch |err| {
                        self.state = .Error;
                        return err;
                    };
                    if (event == .EndOfMessage) {
                        self.state = .Done;
                    }
                    return event;
                },
                .Done => {
                    self.state = .Closed;
                    return .ConnectionClosed;
                },
                .Closed => .ConnectionClosed,
                .Error => error.RemoteProtocolError,
            };
        }

        fn readResponse(self: *Self) !Event {
            var raw_response = try self.readRawResponse();

            var response = Response.parse(self.allocator, raw_response) catch |err| {
                self.allocator.free(raw_response);
                return err;
            };
            errdefer response.deinit();

            self.body_reader = try BodyReader.frame(self.expected_request.?.method, response.statusCode, response.headers);

            return Event{ .Response = response };
        }

        fn readData(self: *Self, options: anytype) !Event {
            if (!@hasField(@TypeOf(options), "buffer")) {
                @panic("You must provide a buffer to read into.");
            }
            return try self.body_reader.?.read(&self.reader, options.buffer);
        }

        fn readRawResponse(self: *Self) ![]u8 {
            var response_buffer = std.ArrayList(u8).init(self.allocator);
            errdefer response_buffer.deinit();

            var buffer: [ReaderLookahead]u8 = undefined;
            var count = try self.reader.read(&buffer);
            if (count == 0) {
                return error.EndOfStream;
            }

            var index = std.mem.indexOf(u8, &buffer, "\r\n\r\n");
            if (index != null) {
                const response = buffer[0 .. index.? + 4];
                try response_buffer.appendSlice(response);
                if (response.len < count) {
                    try self.reader.putBack(buffer[response.len..count]);
                }
                return response_buffer.toOwnedSlice();
            }

            try response_buffer.appendSlice(buffer[0..count]);
            try self.reader.putBack(buffer[count - 3 .. count]);

            while (true) {
                if (response_buffer.items.len > MaximumResponseSize) {
                    return error.ResponseTooLarge;
                }

                count = try self.reader.read(&buffer);
                if (count == 0) {
                    return error.EndOfStream;
                }

                index = std.mem.indexOf(u8, &buffer, "\r\n\r\n");
                if (index != null) {
                    const response_end = index.? + 4;
                    try response_buffer.appendSlice(buffer[3..response_end]);

                    var body = buffer[response_end..count];
                    try self.reader.putBack(body);
                    break;
                }

                try response_buffer.appendSlice(buffer[3..count]);
                try self.reader.putBack(buffer[count - 3 .. count]);
            }

            return response_buffer.toOwnedSlice();
        }
    };
}

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const Headers = @import("http").Headers;

const TestServerSM = ServerSM(std.io.FixedBufferStream([]const u8).Reader);

test "NextEvent - Can retrieve a Response event when state is Idle" {
    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 0\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(std.testing.allocator, reader);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    var event = try server.nextEvent(.{});
    try expect(event.Response.statusCode == .Ok);
    try expect(event.Response.version == .Http11);
    try expect(server.state == .SendBody);
    event.Response.deinit();

    var buffer: [100]u8 = undefined;
    event = try server.nextEvent(.{ .buffer = &buffer });
    try expect(event == .EndOfMessage);
}

test "NextEvent - Can retrieve a Response and Data when state is Idle" {
    const content = "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Length: 14\r\n\r\nGotta go fast!";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(std.testing.allocator, reader);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    var event = try server.nextEvent(.{});
    try expect(event.Response.statusCode == .Ok);
    try expect(event.Response.version == .Http11);
    try expect(server.state == .SendBody);
    event.Response.deinit();

    var buffer: [100]u8 = undefined;
    event = try server.nextEvent(.{ .buffer = &buffer });
    try expectEqualStrings(event.Data.bytes, "Gotta go fast!");
    try expectEqualStrings(buffer[0..14], "Gotta go fast!");
    try expect(server.state == .SendBody);

    event = try server.nextEvent(.{ .buffer = &buffer });
    try expect(event == .EndOfMessage);
    try expect(server.state == .Done);
}

test "NextEvent - When the response size is above the limit - Returns ResponseTooLarge" {
    const content = "HTTP/1.1 200 OK\r\nCookie: " ++ "a" ** 65_000 ++ "\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(std.testing.allocator, reader);
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    const failure = server.nextEvent(.{});

    try expectError(error.ResponseTooLarge, failure);
}

test "NextEvent - When fail to read from the reader - Returns reader' error" {
    const FailingReader = struct {
        const Self = @This();
        const ReadError = error{Failed};
        const Reader = std.io.Reader(*Self, ReadError, read);

        fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *Self, _: []u8) ReadError!usize {
            _ = self;
            return error.Failed;
        }
    };

    var failing_reader = FailingReader{};
    var server = ServerSM(FailingReader.Reader).init(std.testing.allocator, failing_reader.reader());
    defer server.deinit();

    var request = Request.default(std.testing.allocator);
    defer request.deinit();
    server.expectEvent(Event{ .Request = request });

    const failure = server.nextEvent(.{});

    try expectError(error.Failed, failure);
}

test "NextEvent - Cannot retrieve a response event if the data is invalid" {
    const content = "INVALID RESPONSE\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(std.testing.allocator, reader);
    defer server.deinit();

    var event = server.nextEvent(.{});

    try expectError(error.Invalid, event);
    try expect(server.state == .Error);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Done" {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(std.testing.allocator, reader);
    server.state = .Done;
    defer server.deinit();

    var event = try server.nextEvent(.{});

    try expect(event == .ConnectionClosed);
    try expect(server.state == .Closed);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Closed" {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(std.testing.allocator, reader);
    server.state = .Closed;
    defer server.deinit();

    var event = try server.nextEvent(.{});

    try expect(event == .ConnectionClosed);
    try expect(server.state == .Closed);
}
