const std = @import("std");
const h11 = @import("h11");

const testing = std.testing;

test "Server - Receive Get request and write response." {
    var server = h11.Server.init(std.testing.allocator);
    defer server.deinit();

    // ----- Receive a request -----

    var requestBytes = to_crlf_string(
        \\GET /json HTTP/1.1
        \\Host: httpbin.org
        \\User-Agent: curl/7.55.1
        \\Accept: */*
        \\
        \\
    );
    defer testing.allocator.free(requestBytes);


    try server.receiveData(requestBytes);

    var event = try server.nextEvent();
    
    switch (event) {
        .Request => |*request| {
            defer testing.allocator.free(request.headers);
            testing.expect(std.mem.eql(u8, request.method, "GET"));
            testing.expect(std.mem.eql(u8, request.target, "/json"));
            testing.expect(std.mem.eql(u8, request.headers[0].name, "host"));
            testing.expect(std.mem.eql(u8, request.headers[0].value, "httpbin.org"));
            testing.expect(std.mem.eql(u8, request.headers[1].name, "user-agent"));
            testing.expect(std.mem.eql(u8, request.headers[1].value, "curl/7.55.1"));
            testing.expect(std.mem.eql(u8, request.headers[2].name, "accept"));
            testing.expect(std.mem.eql(u8, request.headers[2].value, "*/*"));
        },
        else => unreachable,
    }

    event = try server.nextEvent();
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
