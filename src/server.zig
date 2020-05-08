const std = @import("std");
const Allocator = std.mem.Allocator;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const EventError = @import("events.zig").EventError;
const EventTag = @import("events.zig").EventTag;
const HeaderField = @import("events.zig").HeaderField;
const Headers = @import("events.zig").Headers;
const Response = @import("events.zig").Response;
const State = @import("states.zig").State;
const StatusCode = @import("response.zig").StatusCode;
const Stream = @import("stream.zig").Stream;

pub const ServerAutomaton = struct {
    allocator: *Allocator,
    contentLength: usize = 0,
    state: State,

    pub fn init(allocator: *Allocator) ServerAutomaton {
        return ServerAutomaton{ .allocator = allocator, .state = State.Idle };
    }

    pub fn nextEvent(self: *ServerAutomaton, stream: *Stream) EventError!Event {
        var event: Event = undefined;

        switch(self.state) {
            .Idle => {
                event = self.nextEventWhenIdle(stream) catch |err| switch (err) {
                    error.NeedData => return err,
                    else => {
                        self.state = .Error;
                        return err;
                    }
                };
            },
            .SendBody => {
                event = self.nextEventWhenSendingBody(stream) catch |err| switch (err) {
                    error.NeedData => return err,
                    else => {
                        self.state = .Error;
                        return err;
                    }
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

    fn nextEventWhenIdle(self: *ServerAutomaton, stream: *Stream) EventError!Event {
        var response = try Response.parse(stream, self.allocator);
        self.contentLength = Headers.getContentLength(response.headers) catch |err| {
            self.allocator.free(response.headers);
            return err;
        };
        return Event{ .Response = response };
    }

    fn nextEventWhenSendingBody(self: *ServerAutomaton, stream: *Stream) EventError!Event {
        var data = try Data.parse(stream, self.contentLength);
        return Event{ .Data = data };
    }

    fn nextEventWhenDone(self: *ServerAutomaton, stream: *Stream) Event {
        return .EndOfMessage;
    }

    pub fn changeState(self: *ServerAutomaton, event: Event) void {
        switch (self.state) {
            .Idle => {
                switch (event) {
                    .Response => {
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

    /// The caller owns the returned memory.
    pub fn send(self: *ServerAutomaton, event: Event) EventError![]const u8 {
        return switch (self.state) {
            .Idle => self.sendWhenIdle(event),
            .SendBody => self.sendWhenSendingBody(event),
            else => blk: {
                self.state = .Error;
                break :blk error.LocalProtocolError;
            },
        };
    }

    fn sendWhenIdle(self: *ServerAutomaton, event: Event) EventError![]const u8 {
        return switch (event) {
            .Response => |response| blk: {
                var result = try response.serialize(self.allocator);

                self.state = .SendBody;

                break :blk result;
            },
            else => blk: {
                self.state = .Error;
                break :blk error.LocalProtocolError;
            },
        };
    }

    fn sendWhenSendingBody(self: *ServerAutomaton, event: Event) EventError![]const u8 {
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

test "NextEvent - Parse a response into events" {
    var content ="HTTP/1.1 200 OK\r\nContent-Length: 0\r\nServer: h11/0.1.0\r\n\r\n".*;
    var stream = Stream.init(&content);

    var server = ServerAutomaton.init(testing.allocator);

    var event = try server.nextEvent(&stream);
    testing.expect(event == EventTag.Response);
    switch(event) {
        .Response => testing.allocator.free(event.Response.headers),
        else => unreachable,
    }

    event = try server.nextEvent(&stream);
    testing.expect(event == EventTag.EndOfMessage);
}

test "NextEvent - Parse a response with payload into events" {
    var content ="HTTP/1.1 200 OK\r\nContent-Length: 12\r\nServer: h11/0.1.0\r\n\r\nHello World!".*;
    var stream = Stream.init(&content);

    var server = ServerAutomaton.init(testing.allocator);

    var event = try server.nextEvent(&stream);
    testing.expect(event == EventTag.Response);
    switch(event) {
        .Response => testing.allocator.free(event.Response.headers),
        else => unreachable,
    }

    event = try server.nextEvent(&stream);
    testing.expect(event == EventTag.Data);

    event = try server.nextEvent(&stream);
    testing.expect(event == EventTag.EndOfMessage);
}

test "NextEvent - Transitions to Error state when returning a RemoteProtocolError" {
    var content ="HTTP/1.1 200 OK\r\nContent-Length: NOT_A_NUMBER\r\nServer: h11/0.1.0\r\n\r\n".*;
    var stream = Stream.init(&content);

    var server = ServerAutomaton.init(testing.allocator);

    var event = server.nextEvent(&stream);
    testing.expectError(EventError.RemoteProtocolError, event);
    testing.expect(server.state == .Error);
}

test "Send - When Idle - Can send a Response event" {
    var server = ServerAutomaton.init(testing.allocator);

    var headers = [_]HeaderField{HeaderField{ .name = "Content-Length", .value = "0" }};
    var response = Response{ .statusCode = .Ok, .headers = &headers };

    var bytesToSend = try server.send(Event{ .Response = response });
    defer testing.allocator.free(bytesToSend);

    testing.expect(std.mem.eql(u8, bytesToSend, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"));
    testing.expect(server.state == .SendBody);
}

test "Send - When Idle - Returns a LocalProtocolError on any non-Response event" {
    var server = ServerAutomaton.init(testing.allocator);

    var bytesToSend = server.send(Event{ .EndOfMessage = undefined });

    testing.expectError(error.LocalProtocolError, bytesToSend);
    testing.expect(server.state == .Error);
}

test "Send - When Sending Body - Can send a Data event" {
    var server = ServerAutomaton.init(testing.allocator);
    server.state = .SendBody;

    var bytesToSend = try server.send(Event{ .Data = Data{ .body = "Hello World!" } });

    testing.expect(std.mem.eql(u8, bytesToSend, "Hello World!"));
    testing.expect(server.state == .SendBody);
}

test "Send - When Sending Body - Can send a EndOfMessage event" {
    var server = ServerAutomaton.init(testing.allocator);
    server.state = .SendBody;

    var bytesToSend = try server.send(.EndOfMessage);
    testing.expect(std.mem.eql(u8, bytesToSend, ""));
    testing.expect(server.state == .Done);
}

test "Send - When Sending Body - Returns a LocalProtocolError on any other events" {
    var server = ServerAutomaton.init(testing.allocator);
    server.state = .SendBody;

    var headers = [_]HeaderField{HeaderField{ .name = "Content-Length", .value = "0" }};
    var response = Response{ .statusCode = .Ok, .headers = &headers };

    var bytesToSend = server.send(Event{ .Response = response });
    testing.expectError(error.LocalProtocolError, bytesToSend);
    testing.expect(server.state == .Error);
}
