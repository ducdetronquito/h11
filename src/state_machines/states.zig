pub const State = enum {
    Idle,
    SendBody,
    Done,
    Closed,
    Error,
};
