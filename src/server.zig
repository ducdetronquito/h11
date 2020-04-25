const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const EventError = @import("events.zig").EventError;
const EventTag = @import("events.zig").EventTag;
const Response = @import("events.zig").Response;
const State = @import("states.zig").State;

pub const ServerAutomaton = struct {
    allocator: *Allocator,
    contentLength: usize = 0,
    state: State,

    pub fn init(allocator: *Allocator) ServerAutomaton {
        return ServerAutomaton{ .allocator = allocator, .state = State.Idle };
    }

    pub fn nextEvent(self: *ServerAutomaton, buffer: *Buffer) EventError!Event {
        var event: Event = undefined;
        switch(self.state) {
            .Idle => event = try self.nextEventWhenIdle(buffer),
            .SendBody => event = try self.nextEventWhenSendingBody(buffer),
            .Done => event = self.nextEventWhenDone(buffer),
            else => {
                self.state = .Error;
                event = .ConnectionClosed;
            }
        }

        self.changeState(event);
        return event;
    }

    fn nextEventWhenIdle(self: *ServerAutomaton, buffer: *Buffer) EventError!Event {
        var response = try Response.parse(buffer, self.allocator);
        self.contentLength = try response.getContentLength();
        return Event{ .Response = response };
    }

    fn nextEventWhenSendingBody(self: *ServerAutomaton, buffer: *Buffer) EventError!Event {
        var data = try Data.parse(buffer, self.contentLength);
        return Event{ .Data = data };
    }

    fn nextEventWhenDone(self: *ServerAutomaton, buffer: *Buffer) Event {
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
