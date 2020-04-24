const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
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

    pub fn nextEvent(self: *ServerAutomaton, buffer: *Buffer) !Event {
        var event: Event = undefined;
        switch(self.state) {
            State.Idle => event = try self.nextEventWhenIdle(buffer),
            State.SendBody => event = try self.nextEventWhenSendingBody(buffer),
            State.Done => event = self.nextEventWhenDone(buffer),
            else => {
                self.state = State.Error;
                event = Event{ .ConnectionClosed = undefined };
            }
        }

        self.changeState(event);
        return event;
    }

    fn nextEventWhenIdle(self: *ServerAutomaton, buffer: *Buffer) !Event {
        var response = try Response.parse(buffer, self.allocator);
        self.contentLength = try response.getContentLength();
        return Event{ .Response = response };
    }

    fn nextEventWhenSendingBody(self: *ServerAutomaton, buffer: *Buffer) !Event {
        var data = try Data.parse(buffer, self.contentLength);
        return Event{ .Data = data };
    }

    fn nextEventWhenDone(self: *ServerAutomaton, buffer: *Buffer) Event {
        return Event{ .EndOfMessage = undefined };
    }

    pub fn changeState(self: *ServerAutomaton, event: Event) void {
        switch (self.state) {
            State.Idle => {
                switch (event) {
                    EventTag.ConnectionClosed => self.state = State.Closed,
                    EventTag.Response => self.state = State.SendBody,
                    else => self.state = State.Error,
                }
            },
            State.SendBody => {
                switch (event) {
                    EventTag.Data => self.state = State.Done,
                    else => self.state = State.Error,
                }
            },
            State.Done => {
                switch (event) {
                    EventTag.ConnectionClosed => self.state = State.Closed,
                    else => self.state = State.Error,
                }
            },
            else => self.state = State.Error,
        }
    }
};
