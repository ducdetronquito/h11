const HeaderMap = @import("http").HeaderMap;
const StatusCode = @import("http").StatusCode;
const Version = @import("http").Version;

pub const Response = struct {
    headers: HeaderMap,
    statusCode: StatusCode,
    version: Version,

    pub fn init(headers: HeaderMap, statusCode: StatusCode, version: Version) Response {
        return Response {
            .headers = headers,
            .statusCode = statusCode,
            .version = version,
        };
    }

    pub fn deinit(self: Response) void {
        self.headers.deinit();
    }
};
