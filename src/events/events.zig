pub const Data = @import("data.zig").Data;
pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;

pub const EventType = enum {
    ConnectionClosed,
    Data,
    EndOfMessage,
    Request,
    Response,
};

pub const Event = union(EventType) {
    ConnectionClosed: void,
    Data: Data,
    EndOfMessage: void,
    Request: Request,
    Response: Response,
};
