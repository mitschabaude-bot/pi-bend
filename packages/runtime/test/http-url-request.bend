import Base
import ../src/http-message.bend as Request
import ../src/http-message.bend as Body
import ../src/http-message.bend as Framing
import ../src/http-message.bend as Head
import ../src/http-message.bend as Endpoint
import ../src/url-record.bend as URL
import ../src/url-scheme.bend as Scheme
import ../src/url-host.bend as Host
import ../src/http-message.bend as Headers
import ../src/http-message.bend as Header
import ./utf8-runner.bend as Scalar

def content(value: Maybe<&2, Body.Content>) -> List<&2, U32>:
  match value:
    case None{}: Nil{}
    case Some{Body.Content{bytes, _}}: bytes

def show(value: Result<&2, &2, Request.URLRequestError, Request.URLPrepared>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{Request.URLPrepared{Endpoint.Endpoint{_, host, port, _, target}, Request.BufferedRequestPrepared{Head.Head{method, bytes}, Framing.BufferedFramingPrepared{Body.Prepared{_, _, body}, _}}}}: Host.serialize(host) ++ "|" ++ U32.show(port) ++ "|" ++ method ++ "|" ++ Scalar.showText(target) ++ "|" ++ String.join(Scalar.showNumbers(bytes), ",") ++ "|" ++ String.join(Scalar.showNumbers(content(body)), ",")

def headers(result: Result<&2, &2, Header.HeaderHeaderError, Headers.Headers>) -> Headers.Headers:
  match result:
    case Done{value}: value
    case Fail{_}: Headers.new()

def url(port: U32) -> URL.URL:
  URL.URL{Scheme.Http{}, "", "", Some{Host.Domain{"127.0.0.1"}}, Some{port}, URL.Hierarchical{"a" <> Nil{}}, Some{""}, Some{"ignored"}}

def run(+port: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(show(Request.prepareURL(url(port), "get", Headers.new(), Body.Absent{})))
    IO.print(show(Request.prepareURL(url(port), "POST", Headers.new(), Body.Text{"hé🙂"})))
    IO.print(show(Request.prepareURL(url(port), "PUT", Headers.new(), Body.Bytes{0 <> 255 <> Nil{}})))
    IO.print(show(Request.prepareURL(url(port), "GET", headers(Headers.set(Headers.new(), "Host", "elsewhere.example:9")), Body.Absent{})))
    IO.print(show(Request.prepareURL(url(port), "POST", Headers.new(), Body.Text{""})))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case value <> Nil{}: run(Scalar.decimal(value, 0))
    case _: IO.die(Unit, 1, "expected local oracle port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
