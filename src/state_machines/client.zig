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

pub const ClientSM = struct {
    allocator: *Allocator,
    state: State,

    pub fn init(allocator: *Allocator) ClientSM {
        return ClientSM{ .allocator = allocator, .state = State.Idle };
    }

    pub fn deinit(self: *ClientSM) void {
        self.state = State.Idle;
    }

    pub fn send(self: *ClientSM, event: Event) SMError![]const u8 {
        return switch (self.state) {
            .Idle => self.sendRequest(event),
            .SendBody => self.sendData(event),
            .Done, .Closed => self.closeConnection(event),
            else => self.triggerLocalProtocolError(),
        };
    }

    fn sendRequest(self: *ClientSM, event: Event) SMError![]const u8 {
        return switch (event) {
            .Request => |request| then: {
                var result = try request.serialize(self.allocator);
                self.state = .SendBody;
                break :then result;
            },
            else => self.triggerLocalProtocolError(),
        };
    }

    fn sendData(self: *ClientSM, event: Event) SMError![]const u8 {
        return switch (event) {
            .Data => |data| data.content,
            .EndOfMessage => then: {
                self.state = .Done;
                break :then "";
            },
            else => self.triggerLocalProtocolError(),
        };
    }

    fn closeConnection(self: *ClientSM, event: Event) SMError![]const u8 {
        return switch (event) {
            .ConnectionClosed => then: {
                self.state = .Closed;
                break :then "";
            },
            else => self.triggerLocalProtocolError(),
        };
    }

    inline fn triggerLocalProtocolError(self: *ClientSM) SMError![]const u8 {
        self.state = .Error;
        return error.LocalProtocolError;
    }
};

const expect = std.testing.expect;
const expectError = std.testing.expectError;

test "Send - Can send a Request event when state is Idle" {
    var client = ClientSM.init(std.testing.allocator);

    var headers = Headers.init(std.testing.allocator);
    _ = try headers.append("Host", "www.ziglang.org");
    _ = try headers.append("GOTTA-GO", "FAST!");
    defer headers.deinit();

    var requestEvent = try Request.init(Method.Get, "/", Version.Http11, headers);

    var result = try client.send(Event{ .Request = requestEvent });
    defer std.testing.allocator.free(result);

    var expected = "GET / HTTP/1.1\r\nHost: www.ziglang.org\r\nGOTTA-GO: FAST!\r\n\r\n";
    expect(std.mem.eql(u8, result, expected));
    expect(client.state == .SendBody);
}

test "Send - Cannot send any other event when state is Idle" {
    var client = ClientSM.init(std.testing.allocator);

    var result = client.send(.EndOfMessage);

    expect(client.state == .Error);
    expectError(error.LocalProtocolError, result);
}

test "Send - Can send a Data event when state is SendBody" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .SendBody;
    var data = Data.to_event(null, "It's raining outside, damned Brittany !");

    var result = try client.send(data);

    expect(client.state == .SendBody);
    expect(std.mem.eql(u8, result, "It's raining outside, damned Brittany !"));
}

test "Send - Can send a EndOfMessage event when state is SendBody" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .SendBody;

    var result = try client.send(.EndOfMessage);

    expect(client.state == .Done);
    expect(std.mem.eql(u8, result, ""));
}

test "Send - Cannot send any other event when state is SendBody" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .SendBody;

    var result = client.send(.ConnectionClosed);

    expect(client.state == .Error);
    expectError(error.LocalProtocolError, result);
}

test "Send - Can send a ConnectionClosed event when state is Done" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .Done;

    var result = try client.send(.ConnectionClosed);

    expect(client.state == .Closed);
    expect(std.mem.eql(u8, result, ""));
}

test "Send - Cannot send any other event when state is Done" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .Done;

    var result = client.send(.EndOfMessage);

    expect(client.state == .Error);
    expectError(error.LocalProtocolError, result);
}

test "Send - Can send a ConnectionClosed event when state is Closed" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .Closed;

    var result = try client.send(.ConnectionClosed);

    expect(client.state == .Closed);
    expect(std.mem.eql(u8, result, ""));
}

test "Send - Cannot send any other event when state is Closed" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .Closed;

    var result = client.send(.EndOfMessage);

    expect(client.state == .Error);
    expectError(error.LocalProtocolError, result);
}

test "Send - Cannot send any event when state is Error" {
    var client = ClientSM.init(std.testing.allocator);
    client.state = .Error;

    var result = client.send(.EndOfMessage);

    expect(client.state == .Error);
    expectError(error.LocalProtocolError, result);
}
