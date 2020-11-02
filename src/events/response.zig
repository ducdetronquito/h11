const Headers = @import("http").Headers;
const StatusCode = @import("http").StatusCode;
const Version = @import("http").Version;

pub const Response = struct {
    headers: Headers,
    statusCode: StatusCode,
    version: Version,

    pub fn init(headers: Headers, statusCode: StatusCode, version: Version) Response {
        return Response {
            .headers = headers,
            .statusCode = statusCode,
            .version = version,
        };
    }

    pub fn deinit(self: Response) void {
        var headers = self.headers;
        headers.deinit();
    }
};
