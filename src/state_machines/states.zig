pub const State = enum {
    Idle,
    SendHeader,
    SendBody,
    Done,
    Closed,
    Error,
};
