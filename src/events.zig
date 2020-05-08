pub const EventError = @import("events/errors.zig").EventError;
pub const Data = @import("events/data.zig").Data;
pub const HeaderField = @import("events/headers.zig").HeaderField;
pub const Headers = @import("events/headers.zig").Headers;
pub const Request = @import("events/request.zig").Request;
pub const Response = @import("events/response.zig").Response;
pub const StatusCode = @import("events/response.zig").StatusCode;

pub const EventTag = enum {
    ConnectionClosed,
    Data,
    EndOfMessage,
    Request,
    Response,
};

pub const Event = union(EventTag) {
    ConnectionClosed: void,
    Data: Data,
    EndOfMessage: void,
    Request: Request,
    Response: Response,
};
