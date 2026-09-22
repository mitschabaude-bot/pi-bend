import Base
import ../src/api/openai-sse.bend as Sse
import ../src/api/openai-responses-stream.bend as Stream
import ../src/api/constrained-sampling.bend as Sampling
import ../src/types.bend as T
import ../src/utils/json.bend as Json
import ../src/utils/schema-json.bend as SchemaJson
import ./api/responses-stream.bend as Harness
import ./api/responses-stream-state.bend as State
import ./api/responses-terminal.bend as TerminalTest
import ./api/responses-messages.bend as Fixture
import ./openai-sse-reader-support.bend as Raw
import ./openai-sse-reader-runner.bend as RawParser
import ./openai-responses-wire-runner.bend as WireTest
import ../../runtime/src/sse-reader.bend as Bytes
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/json-parse.bend as Parse
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/callback.bend as Cb
import ../../runtime/test/utf8-runner.bend as Codec

# Raw SSE chunks through the SDK stream cursor and the public processor. Byte
# reads, closes, hooks and emissions share one ordered trace.
type Trace is Data:
  Trace{emits: Nat, reversed: List<&2, V.Value>}

type Environment is Data:
  Environment{inputs: Ref.Ref<List<&2, Raw.Input>>, capture: Ref.Ref<Trace>, closeMode: String}

type Pipe is Type:
  Pipe{cursor: Sse.Cursor<String>, capture: Ref.Ref<Trace>, mode: Harness.Mode}

def E() -> Data: Stream.ReaderError<String>

def logged(text: V.Value, trace: Trace) -> Trace & Unit:
  match trace:
    case Trace{emits, reversed}: (Trace{emits, text <> reversed}, Unit{})

def log(capture: Ref.Ref<Trace>, value: V.Value) -> IO(Unit):
  Ref.modify(Trace, Unit, capture, trace => logged(value, trace))

def pop(inputs: List<&2, Raw.Input>) -> List<&2, Raw.Input> & Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>:
  match inputs:
    case Nil{}: (Nil{}, Done{None{}})
    case Raw.ReadError{} <> rest: (rest, Fail{Sse.Failure{"read failed"}})
    case Raw.ReadAbort{} <> rest: (rest, Fail{Sse.Aborted{}})
    case Raw.ChunkStep{chunk} <> rest: (rest, Done{Some{chunk}})

def readCallback(env: Environment, unused: Unit) -> IO(Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>):
  match env:
    case Environment{inputs, capture, _}:
      do IO<Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>>:
        log(capture, V.Text{"read"})
        Ref.modify(List<&2, Raw.Input>, Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>, inputs, pop)

def closeCallback(env: Environment, unused: Unit) -> IO(Result<&2, &2, Sse.ReadError<String>, Unit>):
  match env:
    case Environment{_, capture, mode}:
      do IO<Result<&2, &2, Sse.ReadError<String>, Unit>>:
        log(capture, V.Text{"close"})
        return Raw.effectResult(mode, "close failed")

def abortCallback(env: Environment, unused: Unit) -> IO(Unit):
  match env:
    case Environment{_, capture, _}: log(capture, V.Text{"abort"})

def diagnosticCallback(env: Environment, cause: Sse.DispatchError) -> IO(Result<&2, &2, Sse.ReadError<String>, Unit>):
  match env cause:
    case Environment{_, capture, _} Sse.InvalidJson{_, _, _, target}:
      do IO<Result<&2, &2, Sse.ReadError<String>, Unit>>:
        log(capture, V.Text{Raw.diagnosticName(target)})
        return Done{Unit{}}
    case _ _: IO.die(Result<&2, &2, Sse.ReadError<String>, Unit>, 1, "unexpected diagnostic")

def advanced(capture: Ref.Ref<Trace>, mode: Harness.Mode, step: Stream.EventStep(String)) -> Pipe & Result<&2, &2, E(), Maybe<&2, Stream.ResponseStreamEvent>>:
  match step:
    case (cursor, result): (Pipe{cursor, capture, mode}, result)

def next(pipe: Pipe) -> IO(Pipe & Result<&2, &2, E(), Maybe<&2, Stream.ResponseStreamEvent>>):
  match pipe:
    case Pipe{cursor, capture, mode}:
      do IO<Pipe & Result<&2, &2, E(), Maybe<&2, Stream.ResponseStreamEvent>>>:
        step : Stream.EventStep(String) <- Stream.nextEvent(String, cursor)
        return advanced(capture, mode, step)

def closed(capture: Ref.Ref<Trace>, mode: Harness.Mode, step: Sse.Cursor<String> & Result<&2, &2, E(), Unit>) -> Pipe & Result<&2, &2, E(), Unit>:
  match step:
    case (cursor, result): (Pipe{cursor, capture, mode}, result)

def close(pipe: Pipe) -> IO(Pipe & Result<&2, &2, E(), Unit>):
  match pipe:
    case Pipe{cursor, capture, mode}:
      do IO<Pipe & Result<&2, &2, E(), Unit>>:
        step : Sse.Cursor<String> & Result<&2, &2, E(), Unit> <- Stream.closeEvents(String, cursor)
        return closed(capture, mode, step)

def emitted(mode: Harness.Mode, event: T.AssistantMessageEvent<V.Value, Unit>, trace: Trace) -> Trace & Result<&2, &2, E(), Unit>:
  match trace:
    case Trace{+emits, reversed}:
      (Trace{1n+emits, V.ObjectValue{R.Record{R.Property{"emit", State.event(event)} <> Nil{}}} <> reversed}, Bool.pick(Result<&2, &2, E(), Unit>, Harness.sinkFailure(mode, emits), Fail{Stream.StreamingFailure{Sse.TransportFailure{"sink failed"}}}, Done{Unit{}}))

def emit(pipe: Pipe, event: T.AssistantMessageEvent<V.Value, Unit>) -> IO(Pipe & Result<&2, &2, E(), Unit>):
  match pipe:
    case Pipe{cursor, +capture, +mode}:
      do IO<Pipe & Result<&2, &2, E(), Unit>>:
        result : Result<&2, &2, E(), Unit> <- Ref.modify(Trace, Result<&2, &2, E(), Unit>, capture, trace => emitted(mode, event, trace))
        return (Pipe{cursor, capture, mode}, result)

def readerText(cause: E()) -> String:
  match cause:
    case Stream.StreamingFailure{Sse.TransportFailure{text}}: text
    case Stream.StreamingFailure{Sse.DiagnosticFailure{text}}: text
    case Stream.StreamingFailure{Sse.DispatchFailure{Sse.InvalidJson{_, _, _, _}}}: "json"
    case Stream.StreamingFailure{Sse.DispatchFailure{Sse.ApiErrorPayload{_}}}: "api"
    case Stream.ProtocolFailure{cause}: "protocol:" ++ WireTest.error(cause)

def errorText(error: Stream.Error<E()>) -> String:
  match error:
    case Stream.ReadFailure{cause}: readerText(cause)
    case Stream.EmitFailure{cause}: readerText(cause)
    case Stream.ContentFailure{value}: Sampling.errorMessage(value)
    case Stream.TerminalFailure{value}: Stream.terminalMessage(value)

def resultError(fields: R.Record<V.Value>, error: Maybe<&2, Stream.Error<E()>>) -> V.Value:
  match error:
    case None{}: V.ObjectValue{fields}
    case Some{value}: V.ObjectValue{R.set(V.Value, fields, "error", V.Text{errorText(value)})}

def resultValue(result: Stream.RunResult<Unit, E()>, trace: Trace) -> V.Value:
  match result trace:
    case Stream.RunResult{output, error} Trace{_, reversed}: resultError(R.Record{R.Property{"output", TerminalTest.snapshot(output)} <> R.Property{"trace", V.ArrayValue{List.reverse(&2, V.Value, reversed)}} <> Nil{}}, error)

# The adapter's own disposal closes an unfinished cursor; here iteration has
# always ended, so this returns the closed successor without effects.
def finished(pair: Pipe & Stream.RunResult<Unit, E()>) -> IO(Stream.RunResult<Unit, E()>):
  match pair:
    case (Pipe{cursor, _, _}, result):
      do IO<Stream.RunResult<Unit, E()>>:
        ignored : Sse.CloseResult<String> <- Sse.close(String, cursor)
        return result

def process(pipe: Pipe) -> IO(Stream.RunResult<Unit, E()>):
  do IO<Stream.RunResult<Unit, E()>>:
    pair : Pipe & Stream.RunResult<Unit, E()> <- Stream.processResponsesStream(~Pipe, ~(E()), ~Unit, ~Unit, ~next, ~close, ~emit, ~Stream.defaultResolveServiceTier, ~(Stream.noServiceTierPricing(Unit)), pipe, TerminalTest.initial(), Fixture.model(False{}, False{}, None{}), Stream.defaultOptions())
    finished(pair)

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
    +capture : Ref.Ref<Trace> <- Ref.new(Trace, Trace{0n, Nil{}})
    +env : Environment = Environment{source, capture, closeMode}
    +read : Cb.Callback<Unit, Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>, ~readCallback, env)
    +closeSource : Cb.Callback<Unit, Result<&2, &2, Sse.ReadError<String>, Unit>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, Sse.ReadError<String>, Unit>, ~closeCallback, env)
    +abort : Cb.Callback<Unit, Unit> <- Cb.create(~Environment, ~Unit, ~Unit, ~abortCallback, env)
    +diagnostic : Cb.Callback<Sse.DispatchError, Result<&2, &2, Sse.ReadError<String>, Unit>> <- Cb.create(~Environment, ~Sse.DispatchError, ~Result<&2, &2, Sse.ReadError<String>, Unit>, ~diagnosticCallback, env)
    result : Stream.RunResult<Unit, E()> <- process(Pipe{Sse.create(String, Bytes.Source{read, closeSource}, Sse.Hooks{abort, diagnostic}, False{}), capture, sinkMode(mode)})
    Cb.dispose(Unit, Result<&2, &2, Sse.ReadError<String>, Maybe<&2, Bytes.Chunk>>, read)
    Cb.dispose(Unit, Result<&2, &2, Sse.ReadError<String>, Unit>, closeSource)
    Cb.dispose(Unit, Unit, abort)
    Cb.dispose(Sse.DispatchError, Result<&2, &2, Sse.ReadError<String>, Unit>, diagnostic)
    remaining : List<&2, Raw.Input> <- Ref.dispose(List<&2, Raw.Input>, source)
    final : Trace <- Ref.dispose(Trace, capture)
    IO.print(Bool.pick(String, equal(resultValue(result, final), Parse.parse(expected)), "pass", "FAIL pipeline snapshot/trace"))

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
