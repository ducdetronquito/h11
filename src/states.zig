pub const State = enum {
    Idle,
    SendResponse,
    SendBody,
    Done,
    MustClose,
    Closed,
    Error,
};
