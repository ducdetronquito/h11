pub const Data = @import("data.zig").Data;
pub const Header = @import("header.zig").Header;
pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;

pub const EventType = enum {
    ConnectionClosed,
    Data,
    EndOfHeader,
    EndOfMessage,
    Header,
    Request,
    Response,
};

pub const Event = union(EventType) {
    ConnectionClosed: void,
    Data: Data,
    EndOfMessage: void,
    EndOfHeader: void,
    Header: Header,
    Request: Request,
    Response: Response,
};
