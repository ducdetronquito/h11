const std = @import("std");
const Allocator = std.mem.Allocator;
const Body = @import("parsers/body.zig").Body;
const Buffer = @import("../buffer.zig").Buffer;
const Data = @import("events.zig").Data;
const Event = @import("events.zig").Event;
const EventError = @import("errors.zig").EventError;
const EventTag = @import("events.zig").EventTag;
const Response = @import("events.zig").Response;
const Headers = @import("parsers/headers.zig").Headers;
const State = @import("states.zig").State;
const StatusLine = @import("parsers/status_line.zig").StatusLine;

pub const ServerAutomaton = struct {
    allocator: *Allocator,
    contentLength: usize = 0,
    state: State,

    pub fn init(allocator: *Allocator) ServerAutomaton {
        return ServerAutomaton{ .allocator = allocator, .state = State.Idle };
    }

    pub fn nextEvent(self: *ServerAutomaton, buffer: *Buffer) !Event {
        var event: Event = undefined;
        if (self.state == State.Idle) {
            event = try self.nextEventWhenIdle(buffer);
        } else if (self.state == State.SendBody) {
            event = try self.nextEventWhenSendingBody(buffer);
        } else {
            self.state = State.Error;
            event = Event{ .ConnectionClosed = undefined };
        }
        self.changeState(event);
        return event;
    }

    fn nextEventWhenIdle(self: *ServerAutomaton, buffer: *Buffer) !Event {
        var statusLine = try StatusLine.parse(buffer);
        var headers = try Headers.parse(self.allocator, buffer);
        errdefer headers.deinit();

        var rawContentLength: []const u8 = "0";
        for (headers.toSliceConst()) |header| {
            if (std.mem.eql(u8, header.name, "content-length")) {
                rawContentLength = header.value;
            }
        }

        const contentLength = std.fmt.parseInt(usize, rawContentLength, 10) catch {
            return EventError.RemoteProtocolError;
        };

        self.contentLength = contentLength;

        return Event{ .Response = Response{ .statusCode = statusLine.statusCode, .headers = headers } };
    }

    fn nextEventWhenSendingBody(self: *ServerAutomaton, buffer: *Buffer) !Event {
        if (!buffer.isEmpty()) {
            var body = try Body.parse(buffer, self.contentLength);
            return Event{ .Data = Data{ .body = body } };
        }

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
                    EventTag.Data => self.state = State.SendBody,
                    EventTag.EndOfMessage => self.state = State.Done,
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
