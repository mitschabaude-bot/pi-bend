import Base
import ../src/api/openai-responses-reader.bend as Reader
import ../src/api/openai-sse-reader.bend as SSE
import ../src/api/openai-sse-json.bend as Json
import ../src/api/openai-responses-stream.bend as Stream
import ../src/api/openai-responses-shared.bend as Shared
import ../src/api/openai-responses-stream-pricing.bend as Pricing
import ../src/types.bend as T
import ./api/responses-stream.bend as Harness
import ./api/responses-terminal.bend as TerminalTest
import ./api/responses-messages.bend as Fixture
import ./openai-sse-reader-support.bend as Raw
import ./openai-sse-reader-runner.bend as RawParser
import ./openai-responses-wire-runner.bend as WireTest
import ../../runtime/src/sse-reader.bend as Bytes
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/json-parse.bend as Parse
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/callback.bend as Cb
import ../../runtime/test/utf8-runner.bend as Codec

type Environment is Data:
  Environment{inputs: Ref.Ref<List<&2, Raw.Input>>, capture: Ref.Ref<Harness.Capture>, closeMode: String}

def pop(inputs: List<&2, Raw.Input>) -> List<&2, Raw.Input> & Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>:
  match inputs:
    case Nil{}: (Nil{}, Done{None{}})
    case Raw.ReadError{} <> rest: (rest, Fail{SSE.Failure{"read failed"}})
    case Raw.ReadAbort{} <> rest: (rest, Fail{SSE.Aborted{}})
    case Raw.ChunkStep{chunk} <> rest: (rest, Done{Some{chunk}})

def readCallback(env: Environment, unused: Unit) -> IO(Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>):
  match env:
    case Environment{inputs, capture, _}:
      do IO<Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>>:
        Harness.log(capture, V.Text{"read"})
        Ref.modify(List<&2, Raw.Input>, Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>, inputs, pop)

def closeCallback(env: Environment, unused: Unit) -> IO(Result<&2, &2, SSE.ReadError<String>, Unit>):
  match env:
    case Environment{_, capture, mode}:
      do IO<Result<&2, &2, SSE.ReadError<String>, Unit>>:
        Harness.log(capture, V.Text{"close"})
        return Raw.effectResult(mode, "close failed")

def abortCallback(env: Environment, unused: Unit) -> IO(Unit):
  match env:
    case Environment{_, capture, _}: Harness.log(capture, V.Text{"abort"})

def diagnosticCallback(env: Environment, cause: Json.Error) -> IO(Result<&2, &2, SSE.ReadError<String>, Unit>):
  match env cause:
    case Environment{_, capture, _} Json.InvalidJson{_, _, _, target}:
      do IO<Result<&2, &2, SSE.ReadError<String>, Unit>>:
        Harness.log(capture, V.Text{Raw.diagnosticName(target)})
        return Done{Unit{}}
    case _ _: IO.die(Result<&2, &2, SSE.ReadError<String>, Unit>, 1, "unexpected diagnostic")

def mapError(cause: Reader.Error<String>) -> String:
  match cause:
    case Reader.StreamingFailure{SSE.TransportFailure{text}}: text
    case Reader.StreamingFailure{SSE.DiagnosticFailure{text}}: text
    case Reader.StreamingFailure{SSE.DispatchFailure{Json.InvalidJson{_, _, _, _}}}: "json"
    case Reader.StreamingFailure{SSE.DispatchFailure{Json.ApiErrorPayload{_}}}: "api"
    case Reader.ProtocolFailure{cause}: "protocol:" ++ WireTest.error(cause)

def requireDisposed(result: Result<&2, &2, Reader.Error<String>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "adapter disposal unexpectedly failed")

def process(sink: Cb.Callback<T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>>, borrowed: Reader.Owner<String, String> & Stream.Reader<String>) -> IO(Stream.RunResult<Unit, String>):
  match borrowed:
    case Tuple{owner, reader}:
      do IO<Stream.RunResult<Unit, String>>:
        result : Stream.RunResult<Unit, String> <- Shared.processResponsesStream(Unit, String, Unit, reader, TerminalTest.initial(), sink, Fixture.model(False{}, False{}, None{}), None{})
        disposed : Result<&2, &2, Reader.Error<String>, Unit> <- Reader.dispose(String, String, owner)
        requireDisposed(disposed)
        return result

def sinkMode(value: String) -> Harness.Mode:
  match value:
    case "1": Harness.SinkFails{0n}
    case "2": Harness.SinkFails{1n}
    case _: Harness.NoHooks{}

def equal(actual: V.Value, expected: Result<&2, &2, Parse.Error, V.Value>) -> Bool:
  match expected:
    case Fail{_}: False{}
    case Done{value}: V.equal(actual, value)

def run(inputs: List<&2, Raw.Input>, closeMode: String, mode: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    +source : Ref.Ref<List<&2, Raw.Input>> <- Ref.new(List<&2, Raw.Input>, inputs)
    +capture : Ref.Ref<Harness.Capture> <- Ref.new(Harness.Capture, Harness.Capture{Nil{}, 0n, 0n, Nil{}})
    +env : Environment = Environment{source, capture, closeMode}
    +read : Cb.Callback<Unit, Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>, ~readCallback, env)
    +close : Cb.Callback<Unit, Result<&2, &2, SSE.ReadError<String>, Unit>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, SSE.ReadError<String>, Unit>, ~closeCallback, env)
    +abort : Cb.Callback<Unit, Unit> <- Cb.create(~Environment, ~Unit, ~Unit, ~abortCallback, env)
    +diagnostic : Cb.Callback<Json.Error, Result<&2, &2, SSE.ReadError<String>, Unit>> <- Cb.create(~Environment, ~Json.Error, ~Result<&2, &2, SSE.ReadError<String>, Unit>, ~diagnosticCallback, env)
    +sink : Cb.Callback<T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>> <- Cb.create(~Harness.Environment, ~T.AssistantMessageEvent<V.Value, Unit>, ~Result<&2, &2, String, Unit>, ~Harness.sinkCallback, Harness.Environment{capture, sinkMode(mode)})
    owner : Reader.Owner<String, String> <- Reader.create(~String, ~String, ~mapError, SSE.create(String, Bytes.Source{read, close}, SSE.Hooks{abort, diagnostic}, False{}))
    result : Stream.RunResult<Unit, String> <- process(sink, Reader.borrow(String, String, owner))
    Cb.dispose(Unit, Result<&2, &2, SSE.ReadError<String>, Maybe<&2, Bytes.Chunk>>, read)
    Cb.dispose(Unit, Result<&2, &2, SSE.ReadError<String>, Unit>, close)
    Cb.dispose(Unit, Unit, abort)
    Cb.dispose(Json.Error, Result<&2, &2, SSE.ReadError<String>, Unit>, diagnostic)
    Cb.dispose(T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>, sink)
    remaining : List<&2, Raw.Input> <- Ref.dispose(List<&2, Raw.Input>, source)
    final : Harness.Capture <- Ref.dispose(Harness.Capture, capture)
    IO.print(Bool.pick(String, equal(Harness.resultValue(result, final), Parse.parse(expected)), "pass", "FAIL pipeline snapshot/trace"))

def text(value: String) -> String:
  Codec.fromScalars(Codec.parseNumbers(value))

def protocol(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case closeMode <> sinkSetting <> chunks <> expected <> Nil{}:
      run(RawParser.inputs(String.split(chunks, '|')), closeMode, sinkSetting, text(expected))
    case _: IO.die(Unit, 1, "invalid pipeline test protocol")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{Chr{115}, encoded} <> rest:
      do IO<Unit>:
        protocol(String.split(encoded, '/'))
        all(rest)
    case _ <> rest: all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
