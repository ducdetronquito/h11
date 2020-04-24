# h11

I/O free HTTP/1.1 implementation for Zig inspired by [hyper/h11](https://github.com/python-hyper/h11)

[![Build Status](https://api.travis-ci.org/ducdetronquito/h11.svg?branch=master)](https://travis-ci.org/ducdetronquito/h11)[![License](https://img.shields.io/badge/license-public%20domain-ff69b4.svg)](https://github.com/ducdetronquito/h11#license)

## Usage

Broadly speaking, *h11* workflow looks like this:

1. Create an `h11.Client` object to track the state of a single HTTP/1.1 connection.
2. To send a request, you need to serialize a `Request` event with `var bytes = client.send(...)` and write those bytes to the network.
3. To receive a response, you read bytes off the network and pass them to `client.receive_data(...)`
4. Then, retrieve one or more HTTP "events" by calling `client.nextEvent()` until it returns an `EndOfMessage` event or an error.


You can find a basic HTTP client written with *h11* [here](https://github.com/ducdetronquito/h11/tree/master/examples/basic_client).

In the end, every concepts of *h11* are taken straight from the original implementation in python: [python-hyper/h11](https://github.com/python-hyper/h11).
Furthermore, a really well written documentation is available [here](https://h11.readthedocs.io).

## License

h11 is released into the Public Domain. 🎉🍻
