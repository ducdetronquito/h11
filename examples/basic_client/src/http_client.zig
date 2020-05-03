const Allocator = std.mem.Allocator;
const EventError = h11.EventError;
const h11 = @import("h11");
const ReadError = std.os.ReadError;
const Response = @import("response.zig").Response;
const std = @import("std");
const Url = @import("url.zig").Url;

pub const ClientError = EventError || ReadError;

pub const HttpClient = struct {
    allocator: *Allocator,
    socket: std.fs.File,
    connection: h11.Client,

    fn connect(allocator: *Allocator, host: []const u8) !HttpClient {
        const port: u16 = 80;
        var socket = try std.net.tcpConnectToHost(allocator, host, port);
        var connection = h11.Client.init(allocator);
        return HttpClient{ .allocator = allocator, .connection = connection, .socket = socket };
    }

    fn deinit(self: *HttpClient) void {
        self.socket.close();
        self.connection.deinit();
    }

    pub fn get(allocator: *Allocator, url: []const u8) !Response {
        var _url = Url.init(url);

        var headers = [_]h11.HeaderField{
            h11.HeaderField{ .name = "Host", .value = _url.host },
            h11.HeaderField{ .name = "User-Agent", .value = "h11/0.1.0" },
            h11.HeaderField{ .name = "Accept", .value = "*/*" },
        };
        var request = h11.Request{ .method = "GET", .target = _url.target, .headers = &headers };

        return try HttpClient.send(allocator, _url.host, request);
    }

    fn send(allocator: *Allocator, host: []const u8, request: h11.Request) !Response {
        var client = try HttpClient.connect(allocator, host);
        defer client.deinit();

        var requestBytes = try client.connection.send(h11.Event{ .Request = request });
        defer allocator.free(requestBytes);

        var nBytes = try client.socket.write(requestBytes);

        _ = try client.connection.send(.EndOfMessage);

        return client.readResponse();
    }

    fn readResponse(self: *HttpClient) ClientError!Response {
        var response = Response.init(self.allocator);

        while (true) {
            var event = try self.nextEvent();

            switch (event) {
                .Response => |*responseEvent| {
                    response.statusCode = responseEvent.statusCode;
                    response.headers = responseEvent.headers;
                },
                .Data => |*dataEvent| {
                    response.body = dataEvent.body;
                },
                .EndOfMessage => {
                    response.buffer = self.connection.buffer.toOwnedSlice();
                    return response;
                },
                else => unreachable,
            }
        }
    }

    fn nextEvent(self: *HttpClient) ClientError!h11.Event {
        while (true) {
            var event = self.connection.nextEvent() catch |err| switch (err) {
                h11.EventError.NeedData => {
                    var responseBuffer = try self.allocator.alloc(u8, 4096);
                    defer self.allocator.free(responseBuffer);
                    var nBytes = try self.socket.read(responseBuffer);
                    try self.connection.receiveData(responseBuffer[0..nBytes]);
                    continue;
                },
                else => {
                    return err;
                },
            };
            return event;
        }
    }
};
