const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const EventError = @import("events.zig").EventError;
const EventTag = @import("events.zig").EventTag;
const Headers = @import("events.zig").Headers;
const HeaderField = @import("events.zig").HeaderField;
const Request = @import("events.zig").Request;
const State = @import("states.zig").State;
const Stream = @import("stream.zig").Stream;

pub const ClientAutomaton = struct {
    allocator: *Allocator,
    contentLength: usize = 0,
    state: State,

    pub fn init(allocator: *Allocator) ClientAutomaton {
        return ClientAutomaton{ .allocator = allocator, .state = State.Idle };
    }

    pub fn nextEvent(self: *ClientAutomaton, stream: *Stream) EventError!Event {
        var event: Event = undefined;
        switch(self.state) {
            .Idle => {
                event = self.nextEventWhenIdle(stream) catch |err| {
                    self.state = .Error;
                    return err;
                };
            },
            .SendBody => {
                event = self.nextEventWhenSendingBody(stream) catch |err| {
                    self.state = .Error;
                    return err;
                };
            },
            .Done => event = self.nextEventWhenDone(stream),
            else => {
                self.state = .Error;
                event = .ConnectionClosed;
            }
        }

        self.changeState(event);
        return event;
    }

    fn nextEventWhenIdle(self: *ClientAutomaton, stream: *Stream) EventError!Event {
        var request = try Request.parse(stream, self.allocator);
        self.contentLength = Headers.getContentLength(request.headers) catch |err| {
            self.allocator.free(request.headers);
            return err;
        };
        return Event{ .Request = request };
    }

    fn nextEventWhenSendingBody(self: *ClientAutomaton, stream: *Stream) EventError!Event {
        var data = try Data.parse(stream, self.contentLength);
        return Event{ .Data = data };
    }

    fn nextEventWhenDone(self: *ClientAutomaton, stream: *Stream) Event {
        return .EndOfMessage;
    }

    pub fn changeState(self: *ClientAutomaton, event: Event) void {
        switch (self.state) {
            .Idle => {
                switch (event) {
                    .Request => {
                        if (self.contentLength == 0) {
                            self.state = .Done;
                        } else {
                            self.state = .SendBody;
                        }
                    },
                    else => self.state = .Error,
                }
            },
            .SendBody => {
                switch (event) {
                    .Data => self.state = .Done,
                    else => self.state = .Error,
                }
            },
            .Done => {
                switch (event) {
                    .ConnectionClosed => self.state = .Closed,
                    else => self.state = .Error,
                }
            },
            else => self.state = .Error,
        }
    }

    pub fn send(self: *ClientAutomaton, event: Event) EventError![]const u8 {
        return switch (self.state) {
            .Idle => self.sendWhenIdle(event),
            .SendBody => self.sendWhenSendingBody(event),
            else => blk: {
                self.state = .Error;
                break :blk error.LocalProtocolError;
            },
        };
    }

    fn sendWhenIdle(self: *ClientAutomaton, event: Event) EventError![]const u8 {
        return switch (event) {
            .Request => |request| blk: {
                var result = try request.serialize(self.allocator);

                self.state = .SendBody;

                break :blk result;
            },
            else => blk: {
                self.state = .Error;
                break :blk error.LocalProtocolError;
            },
        };
    }

    fn sendWhenSendingBody(self: *ClientAutomaton, event: Event) EventError![]const u8 {
        return switch (event) {
            .Data => |value| value.body,
            .EndOfMessage => blk: {
                self.state = .Done;
                break :blk "";
            },
            else => blk: {
                self.state = .Error;
                break :blk error.LocalProtocolError;
            },
        };
    }
};

const testing = std.testing;

test "Send - When Idle - Can send a Request event" {
    var client = ClientAutomaton.init(testing.allocator);

    var headers = [_]HeaderField{HeaderField{ .name = "Host", .value = "httpbin.org" }};
    var request = Request{ .method = "GET", .target = "/xml", .headers = &headers };

    var bytesToSend = try client.send(Event{ .Request = request });
    defer testing.allocator.free(bytesToSend);

    testing.expect(std.mem.eql(u8, bytesToSend, "GET /xml HTTP/1.1\r\nHost: httpbin.org\r\n\r\n"));
    testing.expect(client.state == .SendBody);
}

test "Send - When Idle - Returns a LocalProtocolError on any non-Request event" {
    var client = ClientAutomaton.init(testing.allocator);

    var bytesToSend = client.send(Event{ .EndOfMessage = undefined });

    testing.expectError(error.LocalProtocolError, bytesToSend);
    testing.expect(client.state == .Error);
}

test "Send - When Sending Body - Can send a Data event" {
    var client = ClientAutomaton.init(testing.allocator);
    client.state = .SendBody;

    var bytesToSend = try client.send(Event{ .Data = Data{ .body = "Hello World!" } });

    testing.expect(std.mem.eql(u8, bytesToSend, "Hello World!"));
    testing.expect(client.state == .SendBody);
}

test "Send - When Sending Body - Can send a EndOfMessage event" {
    var client = ClientAutomaton.init(testing.allocator);
    client.state = .SendBody;

    var bytesToSend = try client.send(.EndOfMessage);
    testing.expect(std.mem.eql(u8, bytesToSend, ""));
    testing.expect(client.state == .Done);
}

test "Send - When Sending Body - Returns a LocalProtocolError on any other events" {
    var client = ClientAutomaton.init(testing.allocator);
    client.state = .SendBody;

    var headers = [_]HeaderField{HeaderField{ .name = "Host", .value = "httpbin.org" }};
    var request = Request{ .method = "GET", .target = "/xml", .headers = &headers };

    var bytesToSend = client.send(Event{ .Request = request });
    testing.expectError(error.LocalProtocolError, bytesToSend);
    testing.expect(client.state == .Error);
}

test "NextEvent - Parse a request into events" {
    var content = "GET /json HTTP/1.1\r\nHost: httpbin.org\r\nUser-Agent: curl/7.55.1\r\nAccept: */*\r\n\r\n".*;
    var stream = Stream.init(&content);

    var client = ClientAutomaton.init(testing.allocator);

    var event = try client.nextEvent(&stream);
    testing.expect(event == EventTag.Request);
    switch(event) {
        .Request => testing.allocator.free(event.Request.headers),
        else => unreachable,
    }

    event = try client.nextEvent(&stream);
    testing.expect(event == EventTag.EndOfMessage);
}

test "NextEvent - Parse a request with payload into events" {
    var content = "POST /txt HTTP/1.1\r\nHost: httpbin.org\r\nContent-Length: 12\r\n\r\nHello World!".*;
    var stream = Stream.init(&content);

    var client = ClientAutomaton.init(testing.allocator);

    var event = try client.nextEvent(&stream);
    testing.expect(event == EventTag.Request);
    switch(event) {
        .Request => testing.allocator.free(event.Request.headers),
        else => unreachable,
    }

    event = try client.nextEvent(&stream);
    testing.expect(event == EventTag.Data);

    event = try client.nextEvent(&stream);
    testing.expect(event == EventTag.EndOfMessage);
}

test "NextEvent - Transitions to Error state when returning a RemoteProtocolError" {
    var content = "GET /json HTTP/1.1\r\nContent-Length: NOT_A_NUMBER\r\n\r\n".*;
    var stream = Stream.init(&content);

    var client = ClientAutomaton.init(testing.allocator);

    var event = client.nextEvent(&stream);
    testing.expectError(EventError.RemoteProtocolError, event);
    testing.expect(client.state == .Error);
}
