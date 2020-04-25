const std = @import("std");
const h11 = @import("h11");

const testing = std.testing;

test "Client - Send Get request and read response." {
    var client = h11.Client.init(std.testing.allocator);
    defer client.deinit();

    // ----- Send a request -----
    var headers = [_]h11.HeaderField{
        h11.HeaderField{ .name = "Host", .value = "httpbin.org" },
        h11.HeaderField{ .name = "User-Agent", .value = "curl/7.55.1" },
        h11.HeaderField{ .name = "Accept", .value = "*/*" },
    };
    var request = h11.Request{ .method = "GET", .target = "/json", .headers = headers[0..] };

    var requestBytes = try client.send(h11.Event{ .Request = request });
    defer std.testing.allocator.free(requestBytes);

    var expectedRequest = to_crlf_string(
        \\GET /json HTTP/1.1
        \\Host: httpbin.org
        \\User-Agent: curl/7.55.1
        \\Accept: */*
        \\
        \\
    );
    defer testing.allocator.free(expectedRequest);
    testing.expect(std.mem.eql(u8, requestBytes, expectedRequest));

    var endOfMessageBytes = try client.send(.EndOfMessage);
    defer std.testing.allocator.free(endOfMessageBytes);

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
    var responseBytes = to_crlf_string(responseHeadersBytes);
    defer testing.allocator.free(responseBytes);
    try client.receiveData(responseBytes);
    try client.receiveData(responseDataBytes);

    var event = try client.nextEvent();
    switch (event) {
        .Response => |*response| {
            defer response.deinit();
            testing.expect(response.statusCode == 200);
            testing.expect(std.mem.eql(u8, response.headers.fields[0].name, "date"));
            testing.expect(std.mem.eql(u8, response.headers.fields[0].value, "Mon, 13 Apr 2020 08:51:00 GMT"));
            testing.expect(std.mem.eql(u8, response.headers.fields[6].name, "access-control-allow-credentials"));
            testing.expect(std.mem.eql(u8, response.headers.fields[6].value, "true"));
        },
        else => unreachable,
    }

    event = try client.nextEvent();
    switch (event) {
        .Data => |*data| {
            testing.expect(std.mem.eql(u8, data.body, responseDataBytes));
        },
        else => unreachable,
    }

    event = try client.nextEvent();
    switch (event) {
        .EndOfMessage => return,
        else => unreachable,
    }
}

/// Dirty hacks to use multi-line strings on Windows but with CRLF line breaks.
fn to_crlf_string(content: []const u8) []const u8 {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    var cursor: usize = 0;

    while (cursor < content.len) {
        if (content[cursor] == '\n') {
            buffer.append('\r') catch unreachable;
        }
        buffer.append(content[cursor]) catch unreachable;
        cursor += 1;
    }

    return buffer.items;
}
