const std = @import("std");
const h11 = @import("h11");

const testing = std.testing;

test "Client - Send Get request and read response." {
    var buffer: [1024 * 8]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    var client = h11.Client.init(allocator);
    defer client.deinit();

    // ----- Send a request -----
    var headers = [_]h11.HeaderField{
        h11.HeaderField{ .name = "Host", .value = "httpbin.org" },
        h11.HeaderField{ .name = "User-Agent", .value = "curl/7.55.1" },
        h11.HeaderField{ .name = "Accept", .value = "*/*" },
    };
    var request = h11.Request{ .method = "GET", .target = "/json", .headers = headers[0..] };

    var requestBytes = try client.send(h11.Event{ .Request = request });
    defer allocator.free(requestBytes);

    var expectedRequest = to_crlf_string(
        \\GET /json HTTP/1.1
        \\Host: httpbin.org
        \\User-Agent: curl/7.55.1
        \\Accept: */*
        \\
        \\
    );
    testing.expect(std.mem.eql(u8, requestBytes, expectedRequest));

    var endOfMessageBytes = try client.send(h11.Event{ .EndOfMessage = undefined });
    defer allocator.free(endOfMessageBytes);

    // ----- Receive a response -----
    var responseHeadersBytes =
        \\HTTP/1.1 200 OK
        \\Date: Mon, 13 Apr 2020 08:51:00 GMT
        \\Content-Type: application/json
        \\Content-Length: 429
        \\Connection: keep-alive
        \\Server: gunicorn/19.9.0
        \\Access-Control-Allow-Origin: *
        \\Access-Control-Allow-Credentials: true
        \\
        \\
    ;

    var responseDataBytes =
        \\{
        \\  "slideshow": {
        \\    "author": "Yours Truly", 
        \\    "date": "date of publication", 
        \\    "slides": [
        \\      {
        \\        "title": "Wake up to WonderWidgets!", 
        \\        "type": "all"
        \\      }, 
        \\      {
        \\        "items": [
        \\          "Why <em>WonderWidgets</em> are great", 
        \\          "Who <em>buys</em> WonderWidgets"
        \\        ], 
        \\        "title": "Overview", 
        \\        "type": "all"
        \\      }
        \\    ], 
        \\    "title": "Sample Slide Show"
        \\  }
        \\}
        \\
    ;
    try client.receiveData(to_crlf_string(responseHeadersBytes));
    try client.receiveData(responseDataBytes);

    var event = try client.nextEvent();
    switch (event) {
        h11.EventTag.Response => |*response| {
            defer response.deinit();
            testing.expect(response.statusCode == 200);
            testing.expect(std.mem.eql(u8, response.headers[0].name, "date"));
            testing.expect(std.mem.eql(u8, response.headers[0].value, "Mon, 13 Apr 2020 08:51:00 GMT"));
            testing.expect(std.mem.eql(u8, response.headers[6].name, "access-control-allow-credentials"));
            testing.expect(std.mem.eql(u8, response.headers[6].value, "true"));
        },
        else => unreachable,
    }

    event = try client.nextEvent();
    switch (event) {
        h11.EventTag.Data => |*data| {
            testing.expect(std.mem.eql(u8, data.body, responseDataBytes));
            defer data.deinit();
        },
        else => unreachable,
    }

    event = try client.nextEvent();
    switch (event) {
        h11.EventTag.EndOfMessage => return,
        else => unreachable,
    }
}

/// Dirty hacks to use multi-line strings on Windows but with CRLF line breaks.
fn to_crlf_string(content: []const u8) []const u8 {
    var buffer = std.ArrayList(u8).init(std.debug.global_allocator);
    var cursor: usize = 0;

    while (cursor < content.len) {
        if (content[cursor] == '\n') {
            buffer.append('\r') catch unreachable;
        }
        buffer.append(content[cursor]) catch unreachable;
        cursor += 1;
    }

    return buffer.toSliceConst();
}
