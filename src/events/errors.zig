const Headers = @import("http").Headers;

pub const ParsingError = error{
    Incomplete,
    Invalid,
    OutOfMemory,
    TooManyHeaders,
} || Headers.Error;
