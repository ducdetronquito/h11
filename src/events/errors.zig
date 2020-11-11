pub const ParsingError = error{
    Incomplete,
    Invalid,
    OutOfMemory,
    TooManyHeaders,
};
