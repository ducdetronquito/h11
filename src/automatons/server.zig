const Event = @import("events.zig").Event;
const State = @import("states.zig").State;


pub const ServerAutomaton = struct {
    state: State,

    pub fn init() ServerAutomaton {
        return ServerAutomaton{ .state = State.Idle };
    }

    pub fn handleEvent(self: *ServerAutomaton, event: Event) void {
        switch (self.state) {
            State.Idle => self.whenIsIdle(event),
            State.SendBody => self.whenIsSendingBody(event),
            State.Done => self.whenIsDone(event),
            _ => self.state = State.Error,
        }
    }

    fn whenIsIdle(self: *ServerAutomaton, event: Event) void {
        switch(event) {
            Event.ConnectionClosed => self.state = State.Closed,
            Event.Response => self.state = State.SendBody,
            _ => self.state = State.Error,
        }
    }

    fn whenIsSendingBody(self: *ServerAutomaton, event: Event) void {
        switch(event) {
            Event.Data => self.state = State.SendBody,
            Event.EndOfMessage => self.state = State.Done,
            _ => self.state = State.Error,
        }
    }

    fn whenIsDone(self: *ServerAutomaton, event: Event) void {
        switch(event) {
            Event.ConnectionClosed => self.state = State.Closed,
            _ => self.state = State.Error,
        }
    }
};
