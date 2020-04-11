const std = @import("std");
const Allocator = std.mem.Allocator;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const EventError = @import("errors.zig").EventError;
const EventTag = @import("events.zig").EventTag;
const HeaderField = @import("parsers/headers.zig").HeaderField;
const Request = @import("events.zig").Request;
const State = @import("states.zig").State;

pub const ClientAutomaton = struct {
    allocator: *Allocator,
    pub state: State,

    pub fn init(allocator: *Allocator) ClientAutomaton {
        return ClientAutomaton{ .allocator = allocator, .state = State.Idle };
    }

    pub fn send(self: *ClientAutomaton, event: Event) ![]const u8 {
        switch (self.state) {
            State.Idle => return try self.sendWhenIdle(event),
            State.SendBody => return try self.sendWhenSendingBody(event),
            else => {
                self.state = State.Error;
                return EventError.LocalProtocolError;
            },
        }
    }

    fn sendWhenIdle(self: *ClientAutomaton, event: Event) ![]const u8 {
        return switch (event) {
            EventTag.Request => {
                self.state = State.SendBody;
                return "Request Line";
            },
            else => {
                self.state = State.Error;
                return EventError.LocalProtocolError;
            },
        };
    }

    fn sendWhenSendingBody(self: *ClientAutomaton, event: Event) ![]const u8 {
        return switch (event) {
            EventTag.Data => |value| return value.body,
            EventTag.EndOfMessage => {
                self.state = State.Done;
                return "";
            },
            else => {
                self.state = State.Error;
                return EventError.LocalProtocolError;
            },
        };
    }
};

const testing = std.testing;

test "Send - When Idle - Can send a Request event" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = ClientAutomaton.init(allocator);

    var headers = [_]HeaderField{HeaderField{ .name = "Host", .value = "httpbin.org" }};
    var request = Request{ .method = "GET", .target = "/xml", .headers = headers[0..] };

    var bytesToSend = try client.send(Event{ .Request = request });
    testing.expect(std.mem.eql(u8, bytesToSend, "Request Line"));
}

test "Send - When Idle - Returns a LocalProtocolError on any non-Request event" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = ClientAutomaton.init(allocator);

    var bytesToSend = client.send(Event{ .EndOfMessage = undefined });
    testing.expectError(EventError.LocalProtocolError, bytesToSend);
    testing.expect(client.state == State.Error);
}

test "Send - When Sending Body - Can send a Data event" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = ClientAutomaton.init(allocator);
    client.state = State.SendBody;

    var bytesToSend = try client.send(Event{ .Data = Data{ .body = "Hello World!" } });
    testing.expect(std.mem.eql(u8, bytesToSend, "Hello World!"));
    testing.expect(client.state == State.SendBody);
}

test "Send - When Sending Body - Can send a EndOfMessage event" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = ClientAutomaton.init(allocator);
    client.state = State.SendBody;

    var bytesToSend = try client.send(Event{ .EndOfMessage = undefined });
    testing.expect(std.mem.eql(u8, bytesToSend, ""));
    testing.expect(client.state == State.Done);
}

test "Send - When Sending Body - Returns a LocalProtocolError on any other events" {
    var buffer: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = ClientAutomaton.init(allocator);
    client.state = State.SendBody;

    var headers = [_]HeaderField{HeaderField{ .name = "Host", .value = "httpbin.org" }};
    var request = Request{ .method = "GET", .target = "/xml", .headers = headers[0..] };

    var bytesToSend = client.send(Event{ .Request = request });
    testing.expectError(EventError.LocalProtocolError, bytesToSend);
    testing.expect(client.state == State.Error);
}
