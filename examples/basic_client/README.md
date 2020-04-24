# Basic HTTP Client 🦎

Make an HTTP request to [http://httpbin.org/json](http://httpbin.org/json) and display
the response status code, headers and body in the standard output.

```sh
zig build run

Status Code: 200
----- Headers -----
date = Fri, 24 Apr 2020 10:46:01 GMT
content-type = application/json
content-length = 429
connection = keep-alive
server = gunicorn/19.9.0
access-control-allow-origin = *
access-control-allow-credentials = true
----- Body -----
{
  "slideshow": {
    "author": "Yours Truly",
    "date": "date of publication",
    "slides": [
      {
        "title": "Wake up to WonderWidgets!",
        "type": "all"
      },
      {
        "items": [
          "Why <em>WonderWidgets</em> are great",
          "Who <em>buys</em> WonderWidgets"
        ],
        "title": "Overview",
        "type": "all"
      }
    ],
    "title": "Sample Slide Show"
  }
}
```


On Windows, you will need to run it via Docker as it requires a plateform that have UNIX sockets.

```sh
zig build -Dtarget=x86_64-linux-gnu && docker build -t basic_client . && docker run --rm basic_client
```
