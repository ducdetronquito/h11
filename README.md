# h11

I/O free HTTP/1.1 implementation for Zig inspired by [hyper/h11](https://github.com/python-hyper/h11)

[![Build Status](https://api.travis-ci.org/ducdetronquito/h11.svg?branch=master)](https://travis-ci.org/ducdetronquito/h11)[![License](https://img.shields.io/badge/license-public%20domain-ff69b4.svg)](https://github.com/ducdetronquito/h11#license)

## Usage

```zig
const h11 = @import("h11.zig");

var connection = h11.Connection.init(an_allocator);
defer connection.deinit();

var data = [_]u8{ 'h', 'e', 'l', 'l', 'o', 'w', 'o', 'r', 'l', 'd', '!'};
connection.receiveData(data);
```

## License

h11 is released into the Public Domain. 🎉🍻
