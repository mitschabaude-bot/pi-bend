import Base
import ../src/api/openai-client.bend as Provider
import ../src/utils/provider-retry.bend as Retry
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/http-response-metadata.bend as Metadata
import ../../runtime/src/http-head.bend as Head
import ../../runtime/src/http-status.bend as Status
import ../../runtime/src/http-header.bend as Header
import ../../runtime/src/http-body-consume.bend as Consume
import ../../runtime/src/http-body-buffer.bend as Buffer
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ../../runtime/test/http-response.bend as Input
import ../../runtime/test/http-body-consume.bend as Show
import ../../runtime/test/utf8-runner.bend as Text

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "some:" ++ Text.showText(text)

def number(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ "," ++ U32.show(low)

def projectedFields(retryable: Bool, value: Retry.ProviderError<String>) -> String:
  match value:
    case Retry.ProviderError{original, message, Some{status}, should, milliseconds, seconds}: "project:" ++ original ++ ":" ++ message ++ ":" ++ number(F.toBits(status)) ++ ":" ++ optional(should) ++ ":" ++ optional(milliseconds) ++ ":" ++ optional(seconds) ++ ":" ++ Bool.pick(String, retryable, "retry", "stop")
    case _: "missing-status"

def projected(+value: Retry.ProviderError<String>) -> String:
  projectedFields(Retry.canRetry(String, value), value)

def projection(value: Retry.RequestFailure<String>) -> String:
  match value:
    case Retry.Provider{value}: projected(value)
    case _: "other"

def closeResult(value: Response.Next<String, Input.State>) -> IO(Unit):
  match value:
    case Response.Next{Response.Closed{_}, result}: IO.print("closed:" ++ Input.result(result))
    case _: IO.die(Unit, 1, "body remained open")

def useBody(read: Bool, body: Response.Body<Input.State>) -> IO(Unit):
  match read:
    case False{}:
      do IO<Unit>:
        value : Response.Next<String, Input.State> <- Response.closeWith(String, Input.State, Input.close, body)
        closeResult(value)
    case True{}:
      do IO<Unit>:
        value : Result<&2, &2, Buffer.Error<String>, List<&2, U32>> <- Consume.bytesWith(~String, ~Input.State, ~Input.read, ~Input.close, 1000n, body)
        IO.print("consumer:" ++ Show.shownBytes(value))

def finished(read: Bool, value: Result<&2, &1, Provider.StatusFailure<String>, Response.Response<Input.State>>) -> IO(Unit):
  match value:
    case Done{Response.Response{+metadata, body}}:
      do IO<Unit>:
        IO.print("accepted:" ++ U32.show(Metadata.status(metadata)))
        useBody(read, body)
    case Fail{Provider.StatusFailure{metadata, body}}:
      IO.print("rejected:" ++ U32.show(Metadata.status(metadata)) ++ ":" ++ Show.shownText(body))

def field(parts: List<&2, String>) -> Header.Header:
  match parts:
    case key <> value <> _: Header.Header{key, value}
    case key <> _: Header.Header{key, ""}
    case _: Header.Header{"x-fixture", ""}

def fields(parts: List<&2, String>) -> List<&2, Header.Header>:
  match parts:
    case Nil{}: Nil{}
    case "" <> rest: fields(rest)
    case first <> rest: field(String.split(first, '=')) <> fields(rest)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case code <> limit <> fails <> read <> headers <> events:
      +metadata = Metadata.fromHead(Head.ResponseHead{Status.StatusLine{1, 1, Text.decimal(code, 0), Nil{}}, fields(String.split(headers, '/'))}, True{})
      do IO<Unit>:
        IO.print(projection(Provider.retryFailure(String, "original", "message", metadata)))
        value : Result<&2, &1, Provider.StatusFailure<String>, Response.Response<Input.State>> <- Provider.acceptWith(~String, ~Input.State, ~Input.read, ~Input.close, U32.to_nat(Text.decimal(limit, 0)), Response.Response{metadata, Response.Open{Input.State{events, String.eq(fails, "1")}, True{}}})
        finished(String.eq(read, "1"), value)
    case _: IO.die(Unit, 1, "expected code limit cleanup read headers events")

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print("case")
        run(String.split(first, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
