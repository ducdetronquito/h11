usingnamespace @import("events/errors.zig");
usingnamespace @import("events/data.zig");
usingnamespace @import("events/headers.zig");
usingnamespace @import("events/request.zig");
usingnamespace @import("events/response.zig");

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
