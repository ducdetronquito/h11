# h11

An HTTP/1.1 parser inspired by [httparse](https://github.com/seanmonstar/httparse).

[![Build Status](https://api.travis-ci.org/ducdetronquito/h11.svg?branch=master)](https://travis-ci.org/ducdetronquito/h11) [![License](https://img.shields.io/badge/license-public%20domain-ff69b4.svg)](https://github.com/ducdetronquito/h11#license) [![Requirements](https://img.shields.io/badge/zig-0.6.0-orange)](https://ziglang.org/)

## Usage

### Request Parser

```zig
const h11 = @import("h11");

var headers: [10]Header = undefined;
var buffer = "GET /index.html HTTP/1.1\r\nHost: example.domain\r\n\r\n".*;

var request = try h11.Request.parse(&buffer, &headers);
```

### Response parser

```zig
const h11 = @import("h11");

var headers: [10]Header = undefined;
var buffer = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\n".*;

var response = try h11.Response.parse(&buffer, &headers);
```

### Structures

- `Request`: A parsed request
- `Response`: A parsed response
- `Header`: A parsed header


### Errors

The `parse` function of `Request` and `Response` can return the following errors.

#### Incomplete

Returned when the parsed buffer does not contain enough data to return a complete `Request` or `Response`.

```zig
const expectError = @import("std").testing.expectError;
const h11 = @import("h11");

var headers: [10]Header = undefined;
var buffer = "GET /index.html HTTP/1.1\r\nHost".*;

var request = h11.Request.parse(&buffer, &headers);
expectError(error.Incomplete, request);
```

#### Invalid

Returned when the parsed buffer does not comply with [RFC 7230](https://tools.ietf.org/html/rfc7230).

```zig
const expectError = @import("std").testing.expectError;
const h11 = @import("h11");

var headers: [10]Header = undefined;
var buffer = "I am not a valid HTTP request".*;

var request = h11.Request.parse(&buffer, &headers);
expectError(error.Invalid, request);
```

#### TooManyHeaders

Returned when the buffer contains more headers than the provided `Header` slice can handle.

```zig
const expectError = @import("std").testing.expectError;
const h11 = @import("h11");

var headers: [0]Header = undefined;
var buffer = "GET /index.html HTTP/1.1\r\nHost: example.domain\r\n\r\n".*;

var request = h11.Request.parse(&buffer, &headers);
expectError(error.TooManyHeaders, request);
```

## Requirements

To work with *h11* you will need the latest stable version of Zig, which is currently Zig 0.6.0.


## License

h11 is released into the Public Domain. 🎉🍻
