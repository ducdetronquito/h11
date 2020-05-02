const std = @import("std");
const Allocator = std.mem.Allocator;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const EventError = @import("events.zig").EventError;
const EventTag = @import("events.zig").EventTag;
const Headers = @import("events.zig").Headers;
const Response = @import("events.zig").Response;
const State = @import("states.zig").State;
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
            .Idle => event = try self.nextEventWhenIdle(stream),
            .SendBody => event = try self.nextEventWhenSendingBody(stream),
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
        self.contentLength = try Headers.getContentLength(response.headers);
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
                    .ConnectionClosed => self.state = .Closed,
                    .Response => self.state = .SendBody,
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
};
