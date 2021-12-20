const Allocator = std.mem.Allocator;
const Data = @import("../events/events.zig").Data;
const Event = @import("../events/events.zig").Event;
const Headers = @import("http").Headers;
const Method = @import("http").Method;
const Request = @import("../events/events.zig").Request;
const State = @import("states.zig").State;
const std = @import("std");
const SMError = @import("errors.zig").SMError;
const Version = @import("http").Version;

pub fn ClientSM(comptime Writer: type) type {
    return struct {
        const Self = @This();
        allocator: Allocator,
        state: State,
        writer: Writer,
        const Error = SMError || Writer.Error;

        pub fn init(allocator: Allocator, writer: Writer) Self {
            return .{ .allocator = allocator, .state = State.Idle, .writer = writer };
        }

        pub fn deinit(self: *Self) void {
            self.state = State.Idle;
        }

        pub fn send(self: *Self, event: Event) Error!void {
            switch (self.state) {
                .Idle => try self.sendRequest(event),
                .SendBody => try self.sendData(event),
                .Done, .Closed => try self.closeConnection(event),
                else => try self.triggerLocalProtocolError(),
            }
        }

        fn sendRequest(self: *Self, event: Event) Error!void {
            switch (event) {
                .Request => |request| {
                    var result = try request.serialize(self.allocator);
                    defer self.allocator.free(result);

                    _ = try self.writer.write(result);
                    self.state = .SendBody;
                },
                else => try self.triggerLocalProtocolError(),
            }
        }

        fn sendData(self: *Self, event: Event) Error!void {
            switch (event) {
                .Data => |data| _ = try self.writer.write(data.bytes),
                .EndOfMessage => self.state = .Done,
                else => try self.triggerLocalProtocolError(),
            }
        }

        fn closeConnection(self: *Self, event: Event) SMError!void {
            switch (event) {
                .ConnectionClosed => self.state = .Closed,
                else => try self.triggerLocalProtocolError(),
            }
        }

        inline fn triggerLocalProtocolError(self: *Self) SMError!void {
            self.state = .Error;
            return error.LocalProtocolError;
        }
    };
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

const TestClientSM = ClientSM(std.io.FixedBufferStream([]u8).Writer);

test "Send - Can send a Request event when state is Idle" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());

    var headers = Headers.init(std.testing.allocator);
    _ = try headers.append("Host", "www.ziglang.org");
    _ = try headers.append("GOTTA-GO", "FAST!");
    defer headers.deinit();

    var requestEvent = try Request.init(Method.Get, "/", Version.Http11, headers);
    try client.send(Event{ .Request = requestEvent });

    var expected = "GET / HTTP/1.1\r\nHost: www.ziglang.org\r\nGOTTA-GO: FAST!\r\n\r\n";
    try expect(std.mem.startsWith(u8, &buffer, expected));
    try expect(client.state == .SendBody);
}

test "Send - Cannot send any other event when state is Idle" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());

    const failure = client.send(.EndOfMessage);

    try expect(client.state == .Error);
    try expectError(error.LocalProtocolError, failure);
}

test "Send - Can send a Data event when state is SendBody" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());

    client.state = .SendBody;
    var data = Event{ .Data = Data{ .bytes = "It's raining outside, damned Brittany !" } };

    try client.send(data);

    try expect(client.state == .SendBody);
    try expect(std.mem.startsWith(u8, &buffer, "It's raining outside, damned Brittany !"));
}

test "Send - Can send a EndOfMessage event when state is SendBody" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .SendBody;

    _ = try client.send(.EndOfMessage);

    try expect(client.state == .Done);
}

test "Send - Cannot send any other event when state is SendBody" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .SendBody;

    const failure = client.send(.ConnectionClosed);

    try expect(client.state == .Error);
    try expectError(error.LocalProtocolError, failure);
}

test "Send - Can send a ConnectionClosed event when state is Done" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .Done;

    _ = try client.send(.ConnectionClosed);

    try expect(client.state == .Closed);
}

test "Send - Cannot send any other event when state is Done" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .Done;

    const failure = client.send(.EndOfMessage);

    try expect(client.state == .Error);
    try expectError(error.LocalProtocolError, failure);
}

test "Send - Can send a ConnectionClosed event when state is Closed" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .Closed;

    _ = try client.send(.ConnectionClosed);

    try expect(client.state == .Closed);
}

test "Send - Cannot send any other event when state is Closed" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .Closed;

    const failure = client.send(.EndOfMessage);

    try expect(client.state == .Error);
    try expectError(error.LocalProtocolError, failure);
}

test "Send - Cannot send any event when state is Error" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    var client = TestClientSM.init(std.testing.allocator, fixed_buffer.writer());
    client.state = .Error;

    const failure = client.send(.EndOfMessage);

    try expect(client.state == .Error);
    try expectError(error.LocalProtocolError, failure);
}
