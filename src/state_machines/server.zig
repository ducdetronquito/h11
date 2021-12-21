const BodyReader = @import("body_reader.zig").BodyReader;
const Event = @import("events/main.zig").Event;
const FramingContext = @import("body_reader.zig").FramingContext;
const Header = @import("events/main.zig").Header;
const Request = @import("events/main.zig").Request;
const Response = @import("events/main.zig").Response;
const Method = @import("http").Method;
const SMError = @import("errors.zig").SMError;
const State = @import("states.zig").State;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const TransferEncoding = @import("encoding.zig").TransferEncoding;

pub fn ServerSM(comptime Reader: type) type {
    return struct {
        const Self = @This();

        body_reader: BodyReader = undefined,
        framing_context: FramingContext = FramingContext {},
        reader: Reader,
        state: State = .Idle,

        pub fn init(reader: Reader) Self {
            return .{ .reader = reader };
        }

        pub fn deinit(self: *Self) void {
            self.body_reader = undefined;
            self.framing_context = FramingContext {};
            self.state = State.Idle;
        }

        pub fn nextEvent(self: *Self, buffer: []u8) !Event {
            return switch (self.state) {
                .Idle => {
                    var event = self.readResponse(buffer) catch |err| {
                        self.state = .Error;
                        return err;
                    };
                    self.state = .SendHeader;
                    return event;
                },
                .SendHeader => {
                    var event = self.readHeader(buffer) catch |err| {
                        self.state = .Error;
                        return err;
                    };
                    if (event == .EndOfHeader) {
                        self.state = .SendBody;
                    }
                    return event;
                },
                .SendBody => {
                    var event = self.readData(buffer) catch |err| {
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

        fn readResponse(self: *Self, buffer: []u8) !Event {
            var response = try Response.parse(self.reader, buffer);
            self.framing_context.status_code = response.status_code;
            return Event { .Response = response };
        }

        fn readHeader(self: *Self, buffer: []u8) !Event {
            const header = (try Header.parse(self.reader, buffer)) orelse {
                self.body_reader = try BodyReader.frame(self.framing_context);
                return .EndOfHeader;
            };

            if (std.ascii.eqlIgnoreCase(header.name, "content-length")) {
                self.framing_context.content_length = std.fmt.parseInt(usize, header.value, 10) catch return error.InvalidContentLength;
                self.framing_context.transfert_encoding = .ContentLength;
            } else if (std.ascii.eqlIgnoreCase(header.name, "transfer-encoding")) {
                if (std.mem.endsWith(u8, header.value, "chunked")) {
                    self.framing_context.transfert_encoding = .Chunked;
                } else {
                    return error.UnknownTranfertEncoding;
                }
            }

            return Event{ .Header = header };
        }

        fn readData(self: *Self, buffer: []u8) !Event {
            return try self.body_reader.read(&self.reader, buffer);
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
    var server = TestServerSM.init(reader);

    var buffer: [100]u8 = undefined;
    var event = try server.nextEvent(&buffer);
    try expect(event.Response.status_code == .Ok);
    try expect(event.Response.version == .Http11);

    event = try server.nextEvent(&buffer);
    try expect(std.mem.eql(u8, event.Header.name, "Server"));
    try expect(std.mem.eql(u8, event.Header.value, "Apache"));

    event = try server.nextEvent(&buffer);
    try expect(std.mem.eql(u8, event.Header.name, "Content-Length"));
    try expect(std.mem.eql(u8, event.Header.value, "0"));

    event = try server.nextEvent(&buffer);
    try expect(event == .EndOfHeader);

    event = try server.nextEvent(&buffer);
    try expect(event == .EndOfMessage);
}

test "NextEvent - Can retrieve a Response and Data when state is Idle" {
    const content = "HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\nGotta go fast!";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(reader);

    var buffer: [100]u8 = undefined;
    var event = try server.nextEvent(&buffer);
    try expect(event.Response.status_code == .Ok);
    try expect(event.Response.version == .Http11);

    event = try server.nextEvent(&buffer);
    try expect(std.mem.eql(u8, event.Header.name, "Content-Length"));
    try expect(std.mem.eql(u8, event.Header.value, "14"));

    event = try server.nextEvent(&buffer);
    try expect(event == .EndOfHeader);

    event = try server.nextEvent(&buffer);
    try expectEqualStrings(event.Data.bytes, "Gotta go fast!");

    event = try server.nextEvent(&buffer);
    try expect(event == .EndOfMessage);
    try expect(server.state == .Done);
}

test "NextEvent - When fail to read from the reader - Returns reader's error" {
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
    var server = ServerSM(FailingReader.Reader).init(failing_reader.reader());

    var buffer: [100]u8 = undefined;
    const failure = server.nextEvent(&buffer);

    try expectError(error.Failed, failure);
}

test "NextEvent - Cannot retrieve a response event if the data is invalid" {
    const content = "INVALID RESPONSE\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(reader);

    var buffer: [100]u8 = undefined;
    var event = server.nextEvent(&buffer);

    try expectError(error.Invalid, event);
    try expect(server.state == .Error);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Done" {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(reader);
    server.state = .Done;

    var buffer: [100]u8 = undefined;
    var event = try server.nextEvent(&buffer);

    try expect(event == .ConnectionClosed);
    try expect(server.state == .Closed);
}

test "NextEvent - Retrieve a ConnectionClosed event when state is Closed" {
    const content = "";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(reader);
    server.state = .Closed;

    var buffer: [100]u8 = undefined;
    var event = try server.nextEvent(&buffer);

    try expect(event == .ConnectionClosed);
    try expect(server.state == .Closed);
}

test "NextEvent - Fail when chunked is not the final encoding" {
    const content = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked, gzip\r\n\r\n";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(reader);

    var buffer: [100]u8 = undefined;
    _ = try server.nextEvent(&buffer);

    const failure = server.nextEvent(&buffer);
    try expectError(error.UnknownTranfertEncoding, failure);
}

test "NextEvent - Fail when the provided content length is invalid" {
    const content = "HTTP/1.1 200 OK\r\nContent-Length: XX\r\n\r\nGotta go fast!";
    var reader = std.io.fixedBufferStream(content).reader();
    var server = TestServerSM.init(reader);

    var buffer: [100]u8 = undefined;
    _ = try server.nextEvent(&buffer);

    const failure = server.nextEvent(&buffer);
    try expectError(error.InvalidContentLength, failure);
}

// test "NextEvent - When the response size is above the limit - Returns ResponseTooLarge" {
//     const content = "HTTP/1.1 200 OK\r\nCookie: " ++ "a" ** 65_000 ++ "\r\n\r\n";
//     var reader = std.io.fixedBufferStream(content).reader();
//     var server = TestServerSM.init(std.testing.allocator, reader);
//     defer server.deinit();

//     var request = Request.default(std.testing.allocator);
//     defer request.deinit();
//     server.expectEvent(Event{ .Request = request });

//     var buffer: [100]u8 = undefined;
//     const failure = server.nextEvent(&buffer);

//     try expectError(error.ResponseTooLarge, failure);
// }
