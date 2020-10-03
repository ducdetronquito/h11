pub const Data = @import("events/data.zig").Data;
pub const Request = @import("events/request.zig").Request;

pub const EventType = enum {
    ConnectionClosed,
    Data,
    EndOfMessage,
    Request,
};

pub const Event = union(EventType) {
    ConnectionClosed: void,
    Data: Data,
    EndOfMessage: void,
    Request: Request,
};
