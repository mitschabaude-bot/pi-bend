import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/headers.bend as ProviderHeaders
import ../utils/json.bend as Wire
import ../utils/provider-retry.bend as Retry
import ../utils/schema-json.bend as Schema
import ./constrained-sampling.bend as Sampling
import ./openai-client.bend as Client
import ./openai-sse.bend as Sse
import ./openai-responses.bend as Responses
import ./openai-responses-stream.bend as Stream
import ./simple-options.bend as Simple
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as H
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response.bend as Metadata
import ../../../runtime/src/http-response.bend as Source
import ../../../runtime/src/http-response.bend as Scope
import ../../../runtime/src/json.bend as Parse
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/sse.bend as Body
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/timer.bend as Timer
import ../../../runtime/src/utf8.bend as UTF8
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/websocket.bend as WS
import ../../../runtime/src/websocket-client.bend as Socket

# pi-mono packages/ai/src/api/openai-codex-responses.ts over SSE: the Codex
# backend's own request lifecycle around the shared Responses preparation
# (buildRequestBody is Responses.prepare with the Codex endpoint) and the
# shared processResponsesStream. Its differences from the SDK path are the
# point of this module: no SDK retries (maxRetries defaults to 0) but its own
# retry policy and friendly usage-limit errors, a timeout that covers only the
# response headers, parseSSE's framing (EOF ends the residual frame) and
# mapCodexEvents (Codex error events, endTurn, and stopping at the first
# terminal response while the body may stay open).
#
# Native WebSocket requests use the shared event processor, with cancellation,
# connect/idle deadlines and pre-start SSE fallback. Session connection caching,
# continuation/reconnect retries and transport diagnostics remain pending.
# zstd request bodies remain absent (upstream permits plain JSON).
def J() -> Data: T.JsonValue

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Reason>

def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def DEFAULT_MAX_RETRIES() -> Nat: 0n

def BASE_DELAY_MS() -> U32: 1000

def DEFAULT_MAX_RETRY_DELAY_MS() -> U32: 60000

# parseSSE
# --------
type Framer is Data:
  Framer{utf8: UTF8.Decoder, buffer: String}

def createFramer() -> Framer: Framer{UTF8.create(), ""}

type Split is Data:
  Split{chunk: String, rest: String}

def keptLine(keep: Bool, line: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}: Space.trim(String.drop(line, 5n)) <> rest
    case False{}: rest

def dataLines(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case +line <> rest: keptLine(String.starts_with(line, "data:"), line, dataLines(rest))

def nonDone(+data: String) -> Maybe<&2, String>:
  match data:
    case SNil{}: None{}
    case "[DONE]": None{}
    case _: Some{data}

def payloadOf(lines: List<&2, String>) -> Maybe<&2, String>:
  match lines:
    case Nil{}: None{}
    case some: nonDone(Space.trim(String.join(some, "\n")))

# One "\n\n"-terminated chunk: its data lines, joined and trimmed; empty data
# and [DONE] carry no event.
def chunkPayload(chunk: String) -> Maybe<&2, String>: payloadOf(dataLines(String.split(chunk, '\n')))

def prepend(value: Maybe<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match value:
    case None{}: reversed
    case Some{payload}: payload <> reversed

type Framing is Data:
  Framing{buffer: String, reversed: List<&2, String>}

type Framed is Data:
  Framed{framer: Framer, payloads: List<&2, String>}

def completed(utf8: UTF8.Decoder, result: Framing) -> Framed:
  match result:
    case Framing{buffer, reversed}: Framed{Framer{utf8, buffer}, List.reverse(&2, String, reversed)}

def utf8Of(framer: Framer) -> UTF8.Decoder:
  match framer:
    case Framer{utf8, _}: utf8

def residual(+buffer: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, Space.blank(buffer), Nil{}, prepend(chunkPayload(buffer), Nil{}))

def finishFraming(result: Framing) -> List<&2, String>:
  match result:
    case Framing{buffer, reversed}: List.append(&2, String, List.reverse(&2, String, reversed), residual(buffer))

# mapCodexEvents
# --------------
type Mapped is Data:
  Skip{}
  Pass{event: Stream.ResponseStreamEvent}
  Final{event: Stream.ResponseStreamEvent, endTurn: Maybe<&2, Bool>}
  Thrown{message: String}

def textValue(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def splitAt(text: String, reversed: String) -> Maybe<&2, Split>:
  match text:
    case SNil{}: None{}
    case SCon{'\n', SCon{'\n', rest}}: Some{Split{String.reverse(reversed), rest}}
    case SCon{char, rest}: splitAt(rest, SCon{char, reversed})

# Each step consumes a "\n\n"-terminated chunk, so the buffer shrinks.
@unsafe def framesFrom(split: Maybe<&2, Split>, +buffer: String, reversed: List<&2, String>) -> Framing:
  match split:
    case None{}: Framing{buffer, reversed}
    case Some{Split{chunk, +rest}}: framesFrom(splitAt(rest, ""), rest, prepend(chunkPayload(chunk), reversed))

def frames(+buffer: String) -> Framing: framesFrom(splitAt(buffer, ""), buffer, Nil{})

def framedText(framer: Framer, utf8: UTF8.Decoder, text: String) -> Framed:
  match framer:
    case Framer{_, buffer}:
      +joined = buffer ++ text
      completed(utf8, frames(joined))

def fieldOf(value: Maybe<&2, V.Value>, name: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: R.get(V.Value, fields, name)
    case _: None{}

# JavaScript `a || b` over optional strings: an empty string is falsy.
def orElse(first: Maybe<&2, String>, second: Maybe<&2, String>) -> Maybe<&2, String>:
  match first:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: second

def jsonText(value: V.Value) -> String: Maybe.default(&2, String, Wire.stringify(Schema.toJson(value)), "")

# extractCodexEventError: top-level code/message first, then error.code/message.
def codexError(+event: V.Value) -> String:
  +nested = fieldOf(Some{event}, "error")
  +code = Maybe.or(&2, String, textValue(fieldOf(Some{event}, "code")), textValue(fieldOf(nested, "code")))
  +message = Maybe.or(&2, String, textValue(fieldOf(Some{event}, "message")), textValue(fieldOf(nested, "message")))
  "Codex error: " ++ Maybe.default(&2, String, orElse(message, code), jsonText(event))

def failedResponse(+event: V.Value) -> String:
  +detail = fieldOf(fieldOf(Some{event}, "response"), "error")
  Maybe.default(&2, String, orElse(textValue(fieldOf(detail, "message")), None{}), "Codex response failed")

def codexStatus(+status: String) -> Bool:
  match status:
    case "completed": True{}
    case "incomplete": True{}
    case "failed": True{}
    case "cancelled": True{}
    case "queued": True{}
    case "in_progress": True{}
    case _: False{}

def normalizedStatus(+fields: R.Record<V.Value>, status: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match status:
    case Some{V.Text{+value}}: Bool.pick(R.Record<V.Value>, codexStatus(value), fields, R.remove(V.Value, fields, "status"))
    case _: R.remove(V.Value, fields, "status")

def normalizedResponse(response: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match response:
    case Some{V.ObjectValue{+fields}}: Some{V.ObjectValue{normalizedStatus(fields, R.get(V.Value, fields, "status"))}}
    case other: other

def booleanOf(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{flag}}: Some{flag}
    case _: None{}

def endTurnOf(response: Maybe<&2, V.Value>) -> Maybe<&2, Bool>: booleanOf(fieldOf(response, "end_turn"))

def withResponse(fields: R.Record<V.Value>, response: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match response:
    case Some{value}: R.set(V.Value, fields, "response", value)
    case None{}: fields

def decoded(result: Result<&2, &2, Parse.Error, Stream.ResponseStreamEvent>) -> Result<&2, &2, String, Stream.ResponseStreamEvent>:
  match result:
    case Done{event}: Done{event}
    case Fail{cause}: Fail{"Invalid Responses event: " ++ Responses.describeDecode(cause)}

def framedDecoded(framer: Framer, decoded: UTF8.Decoded) -> Framed:
  match decoded:
    case UTF8.Decoded{utf8, text}: framedText(framer, utf8, text)

def frameBytes(+framer: Framer, bytes: List<&2, U32>) -> Framed: framedDecoded(framer, UTF8.decode(utf8Of(framer), bytes))

def frameChunk(+framer: Framer, chunk: Body.Chunk) -> Framed:
  match chunk:
    case Body.Bytes{bytes}: frameBytes(framer, bytes)
    case Body.Text{text}: framedText(framer, utf8Of(framer), text)
    case Body.EmptyChunk{}: Framed{framer, Nil{}}

def flushedText(framer: Framer, decoded: UTF8.Decoded) -> List<&2, String>:
  match framer decoded:
    case Framer{_, buffer} UTF8.Decoded{_, text}:
      +joined = buffer ++ text
      finishFraming(frames(joined))

# EOF terminates the residual frame ("buffer += \n\n" when it is not blank).
def finishFramer(+framer: Framer) -> List<&2, String>: flushedText(framer, UTF8.finish(utf8Of(framer)))

def finalEvent(result: Result<&2, &2, String, Stream.ResponseStreamEvent>, turn: Maybe<&2, Bool>) -> Mapped:
  match result:
    case Done{event}: Final{event, turn}
    case Fail{message}: Thrown{message}

def passEvent(result: Result<&2, &2, String, Stream.ResponseStreamEvent>) -> Mapped:
  match result:
    case Done{event}: Pass{event}
    case Fail{message}: Thrown{message}

# A terminal response becomes response.completed with a normalized status.
def terminal(+fields: R.Record<V.Value>) -> Mapped:
  +response = R.get(V.Value, fields, "response")
  finalEvent(decoded(Stream.decodeEvent(V.ObjectValue{withResponse(R.set(V.Value, fields, "type", V.Text{"response.completed"}), normalizedResponse(response))})), endTurnOf(response))

def byType(+kind: String, +fields: R.Record<V.Value>) -> Mapped:
  match kind:
    case "error": Thrown{codexError(V.ObjectValue{fields})}
    case "response.failed": Thrown{failedResponse(V.ObjectValue{fields})}
    case "response.done": terminal(fields)
    case "response.completed": terminal(fields)
    case "response.incomplete": terminal(fields)
    case _: passEvent(decoded(Stream.decodeEvent(V.ObjectValue{fields})))

def typed(kind: Maybe<&2, V.Value>, +fields: R.Record<V.Value>) -> Mapped:
  match kind:
    case Some{V.Text{SCon{c, cs}}}: byType(SCon{c, cs}, fields)
    case _: Skip{}

def mapValue(value: V.Value) -> Mapped:
  match value:
    case V.ObjectValue{+fields}: typed(R.get(V.Value, fields, "type"), fields)
    case _: Skip{}

def parseErrorText(cause: Parse.ParseError) -> String:
  match cause:
    case Parse.ParseInvalidValue{}: "invalid value"
    case Parse.InvalidEscape{}: "invalid escape"
    case Parse.UnescapedControl{}: "unescaped control character"
    case Parse.UnterminatedString{}: "unterminated string"
    case Parse.UnexpectedToken{}: "unexpected token"
    case Parse.UnexpectedEnd{}: "unexpected end"
    case Parse.TrailingInput{}: "trailing input"
    case Parse.InputLimit{}: "input limit exceeded"

def mapParsed(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Mapped:
  match result:
    case Done{value}: mapValue(value)
    case Fail{cause}: Thrown{"Invalid Codex SSE JSON: " ++ parseErrorText(cause)}

# One data payload through JSON.parse and mapCodexEvents.
def mapPayload(+payload: String) -> Mapped: mapParsed(Parse.parse(payload))

def aborted() -> String: "Request was aborted"

def mergedTurn(turn: Maybe<&2, Bool>, previous: Maybe<&2, Bool>) -> Maybe<&2, Bool>: Maybe.or(&2, Bool, turn, previous)

def readFailure(~E: Data, ~describe: E -> String, stopped: Bool, cause: E) -> String:
  match stopped:
    case True{}: aborted()
    case False{}: describe(cause)

# The event source
# ----------------
# parseSSE and mapCodexEvents as the source of processResponsesStream: data
# payloads are queued as chunks are framed; the first terminal response stops
# reading (the body may stay open); cancellation is observed before and after
# each read, as upstream's reader loop does.
type CodexSource<-Reason: Data, -E: Data, -G: Data> is Data:
  CodexSource{body: Body.Source<E>, framer: Framer, queue: List<&2, String>, ended: Bool, endTurn: Maybe<&2, Bool>, parent: Signal(Reason), events: EventStream(G)}

def SourceStep(-Reason: Data, -E: Data, -G: Data) -> Type: CodexSource<Reason, E, G> & Result<&2, &2, String, Maybe<&2, Stream.ResponseStreamEvent>>

type Pull<-Reason: Data, -E: Data, -G: Data> is Data:
  Queued{source: CodexSource<Reason, E, G>, payload: String, rest: List<&2, String>}
  Exhausted{source: CodexSource<Reason, E, G>}
  Refill{source: CodexSource<Reason, E, G>}

def atEnd(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>) -> CodexSource<Reason, E, G>:
  match source:
    case CodexSource{body, +framer, queue, _, turn, parent, events}: CodexSource{body, createFramer(), List.append(&2, String, queue, finishFramer(framer)), True{}, turn, parent, events}

def pullOf(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>) -> Pull<Reason, E, G>:
  match source:
    case CodexSource{body, framer, payload <> rest, ended, turn, parent, events}: Queued{CodexSource{body, framer, Nil{}, ended, turn, parent, events}, payload, rest}
    case CodexSource{body, framer, Nil{}, True{}, turn, parent, events}: Exhausted{CodexSource{body, framer, Nil{}, True{}, turn, parent, events}}
    case other: Refill{other}

def withQueue(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>, queue: List<&2, String>, ended: Bool, turn: Maybe<&2, Bool>) -> CodexSource<Reason, E, G>:
  match source:
    case CodexSource{body, framer, _, _, previous, parent, events}: CodexSource{body, framer, queue, ended, mergedTurn(turn, previous), parent, events}

def withFramer(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>, framed: Framed) -> CodexSource<Reason, E, G>:
  match source framed:
    case CodexSource{body, _, queue, ended, turn, parent, events} Framed{framer, payloads}: CodexSource{body, framer, List.append(&2, String, queue, payloads), ended, turn, parent, events}

def framerOf(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>) -> Framer:
  match source:
    case CodexSource{_, framer, _, _, _, _, _}: framer

def bodyOf(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>) -> Body.Source<E>:
  match source:
    case CodexSource{body, _, _, _, _, _, _}: body

def parentOf(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>) -> Signal(Reason):
  match source:
    case CodexSource{_, _, _, _, _, parent, _}: parent

def failedStep(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>, message: String) -> SourceStep(Reason, E, G): (source, Fail{message})

type Phase<-Reason: Data, -E: Data, -G: Data> is Data:
  Pulling{source: CodexSource<Reason, E, G>}
  Mapping{source: CodexSource<Reason, E, G>, value: Mapped}
  Reading{source: CodexSource<Reason, E, G>, before: Bool}
  Received{source: CodexSource<Reason, E, G>, after: Bool, result: Result<&2, &2, E, Maybe<&2, Body.Chunk>>}
  Yielded{source: CodexSource<Reason, E, G>, result: Result<&2, &2, String, Maybe<&2, Stream.ResponseStreamEvent>>}

def pulled(-Reason: Data, -E: Data, -G: Data, pull: Pull<Reason, E, G>) -> Phase<Reason, E, G>:
  match pull:
    case Queued{rest, payload, queue}: Mapping{withQueue(Reason, E, G, rest, queue, False{}, None{}), mapPayload(payload)}
    case Exhausted{rest}: Yielded{rest, Done{None{}}}
    case Refill{rest}: Reading{rest, False{}}

# Queued payloads are consumed before cancellation is checked for a new read.
def readyPhase(-Reason: Data, -E: Data, -G: Data, pull: Pull<Reason, E, G>, before: Bool) -> Phase<Reason, E, G>:
  match pull:
    case Refill{rest}: Reading{rest, before}
    case other: pulled(Reason, E, G, other)

def mappedPhase(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>, value: Mapped) -> Phase<Reason, E, G>:
  match value:
    case Skip{}: Pulling{source}
    case Pass{event}: Yielded{source, Done{Some{event}}}
    case Final{event, turn}: Yielded{withQueue(Reason, E, G, source, Nil{}, True{}, turn), Done{Some{event}}}
    case Thrown{message}: Yielded{source, Fail{message}}

def receivedPhase(~E: Data, ~describe: E -> String, -Reason: Data, -G: Data, +source: CodexSource<Reason, E, G>, after: Bool, result: Result<&2, &2, E, Maybe<&2, Body.Chunk>>) -> Phase<Reason, E, G>:
  match after result:
    case _ Fail{cause}: Yielded{source, Fail{readFailure(~E, ~describe, after, cause)}}
    case True{} _: Yielded{source, Fail{aborted()}}
    case False{} Done{None{}}: Pulling{atEnd(Reason, E, G, source)}
    case False{} Done{Some{chunk}}: Pulling{withFramer(Reason, E, G, source, frameChunk(framerOf(Reason, E, G, source), chunk))}

# upstream parseSSE's reader loop, pulled one event at a time.
@unsafe def advance(~Reason: Data, ~E: Data, ~G: Data, ~describe: E -> String, phase: Phase<Reason, E, G>) -> IO(SourceStep(Reason, E, G)):
  match phase:
    case Pulling{+source}:
      do IO<SourceStep(Reason, E, G)>:
        before : Bool <- Abort.aborted(Reason, parentOf(Reason, E, G, source))
        advance(~Reason, ~E, ~G, ~describe, readyPhase(Reason, E, G, pullOf(Reason, E, G, source), before))
    case Mapping{source, value}: advance(~Reason, ~E, ~G, ~describe, mappedPhase(Reason, E, G, source, value))
    case Reading{source, True{}}: IO.pure(SourceStep(Reason, E, G), (source, Fail{aborted()}))
    case Reading{+source, False{}}:
      do IO<SourceStep(Reason, E, G)>:
        result : Result<&2, &2, E, Maybe<&2, Body.Chunk>> <- Body.read(E, bodyOf(Reason, E, G, source))
        after : Bool <- Abort.aborted(Reason, parentOf(Reason, E, G, source))
        advance(~Reason, ~E, ~G, ~describe, receivedPhase(~E, ~describe, Reason, G, source, after, result))
    case Received{source, after, result}: advance(~Reason, ~E, ~G, ~describe, receivedPhase(~E, ~describe, Reason, G, source, after, result))
    case Yielded{source, result}: IO.pure(SourceStep(Reason, E, G), (source, result))

def nextEvent(~Reason: Data, ~E: Data, ~G: Data, ~describe: E -> String, source: CodexSource<Reason, E, G>) -> IO(SourceStep(Reason, E, G)):
  advance(~Reason, ~E, ~G, ~describe, Pulling{source})

# The reader is released by the caller after processing.
def closeSource(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>) -> IO(CodexSource<Reason, E, G> & Result<&2, &2, String, Unit>):
  IO.pure(CodexSource<Reason, E, G> & Result<&2, &2, String, Unit>, (source, Done{Unit{}}))

def emitEvent(-Reason: Data, -E: Data, -G: Data, source: CodexSource<Reason, E, G>, event: T.AssistantMessageEvent<V.Value, G>) -> IO(CodexSource<Reason, E, G> & Result<&2, &2, String, Unit>):
  match source:
    case CodexSource{body, framer, queue, done, turn, parent, +events}:
      do IO<CodexSource<Reason, E, G> & Result<&2, &2, String, Unit>>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, event)
        return (CodexSource{body, framer, queue, done, turn, parent, events}, Done{Unit{}})

def describeBodyRead(-Reason: Data, error: Sse.ReadError<Sse.TransportError(Reason)>) -> String:
  match error:
    case Sse.Aborted{}: "Request was aborted"
    case Sse.Failure{_}: "terminated"

# Retry helpers
# -------------
def containsAny(+haystack: String, needles: List<&2, String>) -> Bool:
  match needles:
    case Nil{}: False{}
    case needle <> rest: String.contains(haystack, needle) || containsAny(haystack, rest)

def gapAfter(found: Bool, +rest: String, +second: String) -> Bool:
  match found:
    case False{}: False{}
    case True{}: String.starts_with(rest, second) || String.starts_with(String.drop(rest, 1n), second)

def gapHere(+haystack: String, +first: String, +second: String) -> Bool:
  gapAfter(String.starts_with(haystack, first), String.drop(haystack, String.length(first)), second)

# JavaScript /a.?b/ over lowercase text: a, at most one character, then b.
def gapAt(+haystack: String, +first: String, +second: String) -> Bool:
  match haystack:
    case SNil{}: False{}
    case SCon{_, rest}: gapHere(haystack, first, second) || gapAt(rest, first, second)

def isTerminalRateLimitError(errorText: String) -> Bool:
  containsAny(Space.asciiLower(errorText), "gousagelimiterror" <> "freeusagelimiterror" <> "monthly usage limit reached" <> "available balance" <> "insufficient_quota" <> "out of budget" <> "quota exceeded" <> "billing" <> Nil{})

def retryableText(errorText: String) -> Bool:
  +lower = Space.asciiLower(errorText)
  gapAt(lower, "rate", "limit") || gapAt(lower, "service", "unavailable") || gapAt(lower, "upstream", "connect") || gapAt(lower, "connection", "refused") || String.contains(lower, "overloaded")

def retryableStatus(+status: U32) -> Bool:
  U32.is_eq(status, 429) || U32.is_eq(status, 500) || U32.is_eq(status, 502) || U32.is_eq(status, 503) || U32.is_eq(status, 504)

# upstream isRetryableError.
def retryableUnlessTerminal(terminal: Bool, +status: U32, +errorText: String) -> Bool:
  match terminal:
    case True{}: False{}
    case False{}: retryableStatus(status) || retryableText(errorText)

def isRetryableError(+status: U32, +errorText: String) -> Bool:
  retryableUnlessTerminal(U32.is_eq(status, 429) && isTerminalRateLimitError(errorText), status, errorText)

def foundValue(result: Result<&2, &2, H.HeaderSyntaxError, Maybe<&2, String>>) -> Maybe<&2, String>:
  match result:
    case Done{value}: value
    case Fail{_}: None{}

def headerValue(headers: H.Headers, name: String) -> Maybe<&2, String>: foundValue(H.get(headers, name))

def finite(+value: F64) -> Bool: F.isFinite(F.decode(value))

def nonNegative(+value: F64) -> F64: F.maximum(F.fromU32(0), value)

def secondsOrDate(isFinite: Bool, +seconds: F64, +dated: F64, +now: F64) -> Maybe<&2, F64>:
  match isFinite:
    case True{}: Some{nonNegative(F.multiply(seconds, F.fromU32(1000)))}
    case False{}: Bool.pick(Maybe<&2, F64>, F.isNaN(dated), None{}, Some{nonNegative(F.subtract(dated, now))})

def secondsDelay(+seconds: F64, dated: F64, +now: F64) -> Maybe<&2, F64>: secondsOrDate(finite(seconds), seconds, dated, now)

def retryAfterDelay(retryAfter: Maybe<&2, String>, dated: F64, now: F64) -> Maybe<&2, F64>:
  match retryAfter:
    case Some{SCon{c, cs}}: secondsDelay(NumberString.toNumber(SCon{c, cs}), dated, now)
    case _: None{}

def millisecondsIf(isFinite: Bool, +millis: F64, fallback: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match isFinite:
    case True{}: Some{nonNegative(millis)}
    case False{}: fallback

def millisecondsOf(+millis: F64, fallback: Maybe<&2, F64>) -> Maybe<&2, F64>: millisecondsIf(finite(millis), millis, fallback)

def millisecondsDelay(retryAfterMs: Maybe<&2, String>, fallback: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match retryAfterMs:
    case Some{+text}: millisecondsOf(NumberString.toNumber(text), fallback)
    case None{}: fallback

def parsedDate(retryAfter: Maybe<&2, String>) -> IO(F64):
  match retryAfter:
    case Some{SCon{c, cs}}:
      do IO<F64>:
        +parser : C.Callback<String, F64> <- Retry.dateParser()
        value : F64 <- C.call(String, F64, parser, SCon{c, cs})
        C.dispose(String, F64, parser)
        return value
    case _: IO.pure(F64, F.nan())

# upstream getRetryAfterDelayMs: retry-after-ms, then retry-after seconds or
# an HTTP date.
def getRetryAfterDelayMs(+headers: H.Headers) -> IO(Maybe<&2, F64>):
  +retryAfter = headerValue(headers, "retry-after")
  do IO<Maybe<&2, F64>>:
    dated : F64 <- parsedDate(retryAfter)
    now : F64 <- Date.now()
    return millisecondsDelay(headerValue(headers, "retry-after-ms"), retryAfterDelay(retryAfter, dated, now))

def numberText(value: F64) -> String: Maybe.default(&2, String, Wire.stringify(T.JsonNumber{value}), "NaN")

def secondsText(+milliseconds: F64) -> String: numberText(F.ceil(F.divide(milliseconds, F.fromU32(1000))))

# upstream validateRetryDelayMs (RetryDelayExceededError is not retried).
def validateRetryDelayMs(+delay: F64, maxRetryDelayMs: Maybe<&2, F64>) -> Result<&2, &2, String, F64>:
  +limit = Maybe.default(&2, F64, maxRetryDelayMs, F.fromU32(DEFAULT_MAX_RETRY_DELAY_MS()))
  Bool.pick(Result<&2, &2, String, F64>, F.isGreater(F.compare(limit, F.fromU32(0))) && F.isGreater(F.compare(delay, limit)), Fail{"Server requested " ++ secondsText(delay) ++ "s retry delay (max: " ++ secondsText(limit) ++ "s)"}, Done{delay})

def backoff(attempt: Nat) -> F64:
  match attempt:
    case 0n: F.fromU32(BASE_DELAY_MS())
    case 1n+rest: F.multiply(F.fromU32(2), backoff(rest))

# parseErrorResponse
# ------------------
def jsRound(value: F64) -> F64: F64.floor(F.add(value, F.divide(F.fromU32(1), F.fromU32(2))))

def planOf(plan: Maybe<&2, String>) -> String:
  match plan:
    case Some{SCon{c, cs}}: " (" ++ String.to_lower(SCon{c, cs}) ++ " plan)"
    case _: ""

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def minutesUntil(resetsAt: Maybe<&2, F64>, now: F64) -> String:
  match resetsAt:
    case Some{+seconds}:
      Bool.pick(String, F.isEqual(F.compare(seconds, F.fromU32(0))), "", " Try again in ~" ++ numberText(nonNegative(jsRound(F.divide(F.subtract(F.multiply(seconds, F.fromU32(1000)), now), F.fromU32(60000))))) ++ " min.")
    case None{}: ""

def usageCode(+code: String) -> Bool:
  +lower = Space.asciiLower(code)
  String.contains(lower, "usage_limit_reached") || String.contains(lower, "usage_not_included") || String.contains(lower, "rate_limit_exceeded")

def friendlyFor(limited: Bool, +detail: Maybe<&2, V.Value>, now: F64) -> Maybe<&2, String>:
  match limited:
    case False{}: None{}
    case True{}: Some{Space.trim("You have hit your ChatGPT usage limit" ++ planOf(textValue(fieldOf(detail, "plan_type"))) ++ "." ++ minutesUntil(numberOf(fieldOf(detail, "resets_at")), now))}

def describedError(+status: U32, +detail: Maybe<&2, V.Value>, +fallback: String, now: F64) -> String:
  +code = Maybe.default(&2, String, orElse(textValue(fieldOf(detail, "code")), textValue(fieldOf(detail, "type"))), "")
  +friendly = friendlyFor(usageCode(code) || U32.is_eq(status, 429), detail, now)
  Maybe.default(&2, String, orElse(friendly, orElse(textValue(fieldOf(detail, "message")), Some{fallback})), fallback)

def errorObject(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{V.ObjectValue{fields}}
    case Some{V.ArrayValue{items}}: Some{V.ArrayValue{items}}
    case _: None{}

def describedDetail(+status: U32, detail: Maybe<&2, V.Value>, fallback: String, now: F64) -> String:
  match detail:
    case None{}: fallback
    case some: describedError(status, some, fallback, now)

def parsedError(+status: U32, parsed: Result<&2, &2, Parse.ParseError, V.Value>, fallback: String, now: F64) -> String:
  match parsed:
    case Done{+value}: describedDetail(status, errorObject(fieldOf(Some{value}, "error")), fallback, now)
    case Fail{_}: fallback

# upstream parseErrorResponse: the friendly usage-limit message when it
# applies, else the error's message, else the raw body or status text.
def parseErrorResponse(+status: U32, statusText: String, +raw: String, now: F64) -> String:
  +fallback = Maybe.default(&2, String, orElse(Some{raw}, orElse(Some{statusText}, None{})), "Request failed")
  parsedError(status, Parse.parse(raw), fallback, now)

# The fetch-with-retry loop
# -------------------------
type Failure<-E: Data> is Data:
  Message{text: String}
  DelayExceeded{text: String}
  HookError{cause: E}
  Cancelled{}

type Attempt<-Reason: Data, -E: Data> is Type:
  Acquired{response: Response.Response<Client.State(Reason)>}
  RetryAfter{delay: F64}
  Failed{failure: Failure<E>}

def headerTimedOut(-Reason: Data, reason: Abort.AbortReason<Deadline.Cause<Reason>>) -> Bool:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: True{}
    case _: False{}

def expired(-Reason: Data, error: Client.FetchError<Reason>) -> Bool:
  match error:
    case Client.FetchFailure{Scope.Aborted{why}}: headerTimedOut(Reason, why)
    case Client.FetchFailure{Scope.DispatchFailure{_, Some{why}}}: headerTimedOut(Reason, why)
    case _: False{}

def headerTimeout(timeout: Maybe<&2, U32>) -> String:
  match timeout:
    case Some{milliseconds}: "Codex SSE response headers timed out after " ++ U32.show(milliseconds) ++ "ms"
    case None{}: "Codex SSE response headers timed out"

# A fetch failure: the header timeout (unless the caller aborted), the caller's
# abort, or the fetch implementation's error ("fetch failed" in Node).
def transportFailure(-Reason: Data, -E: Data, +timeout: Maybe<&2, U32>, parentAborted: Bool, error: Client.FetchError<Reason>) -> Failure<E>:
  match parentAborted:
    case True{}: Cancelled{}
    case False{}: Bool.pick(Failure<E>, expired(Reason, error), Message{headerTimeout(timeout)}, Message{"fetch failed"})

def statusDelay(-Reason: Data, -E: Data, validated: Result<&2, &2, String, F64>) -> Attempt<Reason, E>:
  match validated:
    case Done{delay}: RetryAfter{delay}
    case Fail{message}: Failed{DelayExceeded{message}}

def bodyText(-E: Data, body: Result<&2, &2, Response.TextError<E>, String>) -> String:
  match body:
    case Done{text}: text
    case Fail{_}: ""

def textOfFailure(-Reason: Data, failure: Client.StatusFailure<Client.ReadError(Reason)>) -> String:
  match failure:
    case Client.StatusFailure{_, body}: bodyText(Client.ReadError(Reason), body)

def metadataOf(-Reason: Data, failure: Client.StatusFailure<Client.ReadError(Reason)>) -> Metadata.Metadata:
  match failure:
    case Client.StatusFailure{metadata, _}: metadata

def retryDelay(-Reason: Data, -E: Data, attempt: Nat, maxRetryDelayMs: Maybe<&2, F64>, serverDelay: Maybe<&2, F64>) -> Attempt<Reason, E>:
  match serverDelay:
    case Some{+delay}: statusDelay(Reason, E, validateRetryDelayMs(delay, maxRetryDelayMs))
    case None{}: RetryAfter{backoff(attempt)}

def statusOutcome(-Reason: Data, -E: Data, retry: Bool, +attempt: Nat, maxRetryDelayMs: Maybe<&2, F64>, +metadata: Metadata.Metadata, +status: U32, +raw: String) -> IO(Attempt<Reason, E>):
  match retry:
    case True{}:
      do IO<Attempt<Reason, E>>:
        serverDelay : Maybe<&2, F64> <- getRetryAfterDelayMs(Metadata.headers(metadata))
        return retryDelay(Reason, E, attempt, maxRetryDelayMs, serverDelay)
    case False{}:
      do IO<Attempt<Reason, E>>:
        now : F64 <- Date.now()
        return Failed{Message{parseErrorResponse(status, Metadata.statusText(metadata), raw, now)}}

# A failed status: retried after its server delay (or the backoff) while
# attempts remain and it is retryable; otherwise parseErrorResponse's message.
def statusFailure(-Reason: Data, -E: Data, +attempt: Nat, +last: Bool, maxRetryDelayMs: Maybe<&2, F64>, +failure: Client.StatusFailure<Client.ReadError(Reason)>) -> IO(Attempt<Reason, E>):
  +metadata = metadataOf(Reason, failure)
  +status = Metadata.metadataStatus(metadata)
  +raw = textOfFailure(Reason, failure)
  statusOutcome(Reason, E, Bool.not(last) && isRetryableError(status, raw), attempt, maxRetryDelayMs, metadata, status, raw)

type Context<-Reason: Data, -E: Data> is Data:
  Context{model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, request: Client.Request, parent: Signal(Reason), fetch: Fetch.Fetch(Reason), timeout: Maybe<&2, U32>, maxRetryDelayMs: Maybe<&2, F64>, diagnosticLimit: Nat}

def contextParent(-Reason: Data, -E: Data, context: Context<Reason, E>) -> Signal(Reason):
  match context:
    case Context{_, _, _, parent, _, _, _, _}: parent

# A timeout of 0 (or none) sets no header deadline.
def headerDeadline(timeout: Maybe<&2, U32>) -> U32:
  match timeout:
    case Some{0}: 4294967295
    case Some{milliseconds}: milliseconds
    case None{}: 4294967295

def accepted(-Reason: Data, -E: Data, +attempt: Nat, +last: Bool, maxRetryDelayMs: Maybe<&2, F64>, result: Result<&2, &1, Client.StatusFailure<Client.ReadError(Reason)>, Response.Response<Client.State(Reason)>>) -> IO(Attempt<Reason, E>):
  match result:
    case Done{response}: IO.pure(Attempt<Reason, E>, Acquired{response})
    case Fail{failure}: statusFailure(Reason, E, attempt, last, maxRetryDelayMs, failure)

def hooked(~Reason: Data, ~E: Data, +attempt: Nat, +last: Bool, maxRetryDelayMs: Maybe<&2, F64>, limit: Nat, pair: Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit>) -> IO(Attempt<Reason, E>):
  match pair:
    case (response, Fail{cause}):
      do IO<Attempt<Reason, E>>:
        released : Result<&2, &2, Response.ResponseProgressError<Client.ReadError(Reason)>, Unit> <- Client.release(Reason, response)
        return Failed{HookError{cause}}
    case (response, Done{_}):
      do IO<Attempt<Reason, E>>:
        result : Result<&2, &1, Client.StatusFailure<Client.ReadError(Reason)>, Response.Response<Client.State(Reason)>> <- Client.acceptWith(~(Client.ReadError(Reason)), ~(Client.State(Reason)), ~(Client.read(Reason)), ~(Client.close(Reason)), limit, response)
        accepted(Reason, E, attempt, last, maxRetryDelayMs, result)

def dispatched(~Reason: Data, ~E: Data, context: Context<Reason, E>, +attempt: Nat, +last: Bool, parentAborted: Bool, result: Result<&2, &1, Client.FetchError<Reason>, Response.Response<Client.State(Reason)>>) -> IO(Attempt<Reason, E>):
  match context result:
    case Context{_, _, _, _, _, timeout, _, _} Fail{cause}: IO.pure(Attempt<Reason, E>, Failed{transportFailure(Reason, E, timeout, parentAborted, cause)})
    case Context{model, hook, _, _, _, _, delay, limit} Done{response}:
      do IO<Attempt<Reason, E>>:
        pair : Response.Response<Client.State(Reason)> & Result<&2, &2, E, Unit> <- Responses.responseHook(Reason, E, model, hook, response)
        hooked(~Reason, ~E, attempt, last, delay, limit, pair)

# One fetch under the header deadline, the response hook, then the status.
def attemptOnce(~Reason: Data, ~E: Data, +context: Context<Reason, E>, +attempt: Nat, +last: Bool) -> IO(Attempt<Reason, E>):
  match context:
    case Context{_, _, request, parent, fetch, timeout, _, _}:
      do IO<Attempt<Reason, E>>:
        result : Result<&2, &1, Client.FetchError<Reason>, Response.Response<Client.State(Reason)>> <- Client.dispatch(Reason, request, parent, fetch, Done{headerDeadline(timeout)})
        parentAborted : Bool <- Abort.aborted(Reason, parent)
        dispatched(~Reason, ~E, context, attempt, last, parentAborted, result)

def Acquisition(-Reason: Data, -E: Data) -> Type: Result<&2, &1, Failure<E>, Response.Response<Client.State(Reason)>>

type Loop<-Reason: Data, -E: Data> is Type:
  Start{attempt: Nat, remaining: Nat}
  Got{attempt: Nat, remaining: Nat, result: Attempt<Reason, E>}
  Wait{attempt: Nat, remaining: Nat, delay: F64}
  Stop{result: Acquisition(Reason, E)}

# upstream's catch: network and other errors are retried after the backoff,
# except aborts, an exceeded server delay and usage-limit messages.
def retryableFailure(~E: Data, ~render: E -> String, failure: Failure<E>) -> Bool:
  match failure:
    case Message{text}: Bool.not(String.contains(text, "usage limit"))
    case DelayExceeded{_}: False{}
    case HookError{cause}: Bool.not(String.contains(render(cause), "usage limit"))
    case Cancelled{}: False{}

def failedAttempt(~E: Data, ~render: E -> String, -Reason: Data, +attempt: Nat, remaining: Nat, +failure: Failure<E>) -> Loop<Reason, E>:
  match remaining:
    case 0n: Stop{Fail{failure}}
    case 1n+rest: Bool.pick(Loop<Reason, E>, retryableFailure(~E, ~render, failure), Wait{attempt, 1n + rest, backoff(attempt)}, Stop{Fail{failure}})

def gotStep(~E: Data, ~render: E -> String, -Reason: Data, +attempt: Nat, +remaining: Nat, result: Attempt<Reason, E>) -> Loop<Reason, E>:
  match result:
    case Acquired{response}: Stop{Done{response}}
    case RetryAfter{delay}: Wait{attempt, remaining, delay}
    case Failed{failure}: failedAttempt(~E, ~render, Reason, attempt, remaining, failure)

def lastAttempt(remaining: Nat) -> Bool:
  match remaining:
    case 0n: True{}
    case _: False{}

def slept(-Reason: Data, -E: Data, +attempt: Nat, remaining: Nat, result: Result<&2, &2, Abort.AbortReason<Reason>, Unit>) -> Loop<Reason, E>:
  match result remaining:
    case Fail{_} _: Stop{Fail{Cancelled{}}}
    case Done{_} 0n: Stop{Fail{Cancelled{}}}
    case Done{_} 1n+rest: Start{1n + attempt, rest}

def sleepMilliseconds(value: Result<&2, &2, Timer.Error, U32>) -> U32:
  match value:
    case Done{milliseconds}: milliseconds
    case Fail{_}: 0

# Each attempt first observes cancellation ("Request was aborted").
def started(~Reason: Data, ~E: Data, +context: Context<Reason, E>, cancelled: Bool, +attempt: Nat, +remaining: Nat) -> IO(Loop<Reason, E>):
  match cancelled:
    case True{}: IO.pure(Loop<Reason, E>, Stop{Fail{Cancelled{}}})
    case False{}:
      do IO<Loop<Reason, E>>:
        result : Attempt<Reason, E> <- attemptOnce(~Reason, ~E, context, attempt, lastAttempt(remaining))
        return Got{attempt, remaining, result}

@unsafe def attempts(~Reason: Data, ~E: Data, ~render: E -> String, +context: Context<Reason, E>, state: Loop<Reason, E>) -> IO(Acquisition(Reason, E)):
  match state:
    case Start{attempt, remaining}:
      do IO<Acquisition(Reason, E)>:
        cancelled : Bool <- Abort.aborted(Reason, contextParent(Reason, E, context))
        next : Loop<Reason, E> <- started(~Reason, ~E, context, cancelled, attempt, remaining)
        attempts(~Reason, ~E, ~render, context, next)
    case Got{attempt, remaining, result}: attempts(~Reason, ~E, ~render, context, gotStep(~E, ~render, Reason, attempt, remaining, result))
    case Wait{attempt, remaining, delay}:
      do IO<Acquisition(Reason, E)>:
        result : Result<&2, &2, Abort.AbortReason<Reason>, Unit> <- Timer.sleep(Reason, sleepMilliseconds(Timer.milliseconds(delay)), contextParent(Reason, E, context))
        attempts(~Reason, ~E, ~render, context, slept(Reason, E, attempt, remaining, result))
    case Stop{result}: IO.pure(Acquisition(Reason, E), result)

# Processing the body
# -------------------
def ReadE(-Reason: Data) -> Data: Sse.ReadError<Sse.TransportError(Reason)>

def processingMessage(error: Stream.Error<String>) -> String:
  match error:
    case Stream.ReadFailure{message}: message
    case Stream.EmitFailure{message}: message
    case Stream.ContentFailure{cause}: Sampling.errorMessage(cause)
    case Stream.TerminalFailure{cause}: Stream.terminalMessage(cause)

# mapCodexEvents sets output.endTurn from a terminal response's end_turn.
def withEndTurn(-G: Data, output: T.AssistantMessage<V.Value, G>, turn: Maybe<&2, Bool>) -> T.AssistantMessage<V.Value, G>:
  match output turn:
    case message None{}: message
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, raw, _, timestamp} Some{value}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, raw, Some{value}, timestamp}

def processedOutcome(-Reason: Data, -G: Data, -E: Data, pair: CodexSource<Reason, ReadE(Reason), G> & Stream.RunResult<G, String>) -> Responses.Outcome<Reason, G, E>:
  match pair:
    case (CodexSource{_, _, _, _, turn, _, _}, Stream.RunResult{output, error}): Responses.Outcome{withEndTurn(G, output, turn), Maybe.map(&2, Stream.Error<String>, Responses.Error<Reason, E>, cause => Responses.OutputFailure{processingMessage(cause)}, error), None{}}

def borrowedBody(~Reason: Data, ~G: Data, ~E: Data, +model: T.Model<J()>, options: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), pair: Sse.Body(Reason) & Body.Source<ReadE(Reason)>) -> IO(Responses.Outcome<Reason, G, E>):
  match pair:
    case (owner, source):
      do IO<Responses.Outcome<Reason, G, E>>:
        result : CodexSource<Reason, ReadE(Reason), G> & Stream.RunResult<G, String> <- Stream.processResponsesStream(~CodexSource<Reason, ReadE(Reason), G>, ~String, ~J(), ~G, ~(nextEvent(~Reason, ~(ReadE(Reason)), ~G, ~(describeBodyRead(Reason)))), ~(closeSource(Reason, ReadE(Reason), G)), ~(emitEvent(Reason, ReadE(Reason), G)), ~Responses.resolveCodexServiceTier, ~Responses.tierPricing, CodexSource{source, createFramer(), Nil{}, False{}, None{}, parent, events}, output, model, options)
        closed : Result<&2, &2, ReadE(Reason), Unit> <- Source.dispose(Client.State(Reason), ReadE(Reason), owner)
        return processedOutcome(Reason, G, E, result)

def streamBody(~Reason: Data, ~G: Data, ~E: Data, +model: T.Model<J()>, options: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), response: Response.Response<Client.State(Reason)>) -> IO(Responses.Outcome<Reason, G, E>):
  match response:
    case Response.Response{_, body}:
      do IO<Responses.Outcome<Reason, G, E>>:
        owner : Sse.Body(Reason) <- Source.create(~(Client.ReadError(Reason)), ~(Client.State(Reason)), ~(ReadE(Reason)), ~(Sse.classify(Reason)), ~(Client.read(Reason)), ~(Client.close(Reason)), body)
        borrowedBody(~Reason, ~G, ~E, model, options, output, events, parent, Source.borrow(Client.State(Reason), ReadE(Reason), owner))

# Continuation is a value owned by its session connection. A failed prefix or
# changed request configuration invalidates it and sends the full context.
type CachedWebSocketContinuationState is Data:
  CachedWebSocketContinuationState{lastRequestBody: R.Record<V.Value>, lastResponseId: String, lastResponseItems: List<&2, V.Value>}
type CachedWebSocketRequest is Data:
  CachedWebSocketRequest{body: R.Record<V.Value>, continuation: Maybe<&2, CachedWebSocketContinuationState>}

def requestBodyWithoutInput(body: R.Record<V.Value>) -> R.Record<V.Value>:
  R.remove(V.Value, R.remove(V.Value, body, "input"), "previous_response_id")

def responseInput(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, V.Value>>:
  match value:
    case None{}: Some{Nil{}}
    case Some{V.ArrayValue{items}}: Some{items}
    case _: None{}

def requestBodiesMatchExceptInput(left: R.Record<V.Value>, right: R.Record<V.Value>) -> Bool:
  V.equal(V.ObjectValue{requestBodyWithoutInput(left)}, V.ObjectValue{requestBodyWithoutInput(right)})

# Remove the baseline only if the entire prefix matches, preserving the
# current input's suffix and array order. An empty delta is valid.
def cachedInputSuffix(current: List<&2, V.Value>, baseline: List<&2, V.Value>, matched: Bool) -> Maybe<&2, List<&2, V.Value>>:
  match matched current baseline:
    case False{} _ _: None{}
    case True{} remaining Nil{}: Some{remaining}
    case True{} Nil{} _ <> _: None{}
    case True{} first <> rest expected <> tail: cachedInputSuffix(rest, tail, V.equal(first, expected))

def cachedInputFields(current: Maybe<&2, List<&2, V.Value>>, previous: Maybe<&2, List<&2, V.Value>>, response: List<&2, V.Value>, matched: Bool) -> Maybe<&2, List<&2, V.Value>>:
  match current previous:
    case Some{input} Some{baseline}: cachedInputSuffix(input, List.append(&2, V.Value, baseline, response), matched)
    case _ _: None{}

def getCachedWebSocketInputDelta(+body: R.Record<V.Value>, continuation: CachedWebSocketContinuationState) -> Maybe<&2, List<&2, V.Value>>:
  match continuation:
    case CachedWebSocketContinuationState{+previous, _, items}:
      cachedInputFields(responseInput(R.get(V.Value, body, "input")), responseInput(R.get(V.Value, previous, "input")), items, requestBodiesMatchExceptInput(body, previous))

def cachedWebSocketBody(+body: R.Record<V.Value>, continuation: CachedWebSocketContinuationState, delta: Maybe<&2, List<&2, V.Value>>) -> CachedWebSocketRequest:
  match continuation delta:
    case CachedWebSocketContinuationState{_, SNil{}, _} _: CachedWebSocketRequest{body, None{}}
    case _ None{}: CachedWebSocketRequest{body, None{}}
    case CachedWebSocketContinuationState{previous, +id, items} Some{input}:
      CachedWebSocketRequest{R.set(V.Value, R.set(V.Value, body, "previous_response_id", V.Text{id}), "input", V.ArrayValue{input}), Some{CachedWebSocketContinuationState{previous, id, items}}}

def buildCachedWebSocketRequestBody(+body: R.Record<V.Value>, continuation: Maybe<&2, CachedWebSocketContinuationState>) -> CachedWebSocketRequest:
  match continuation:
    case None{}: CachedWebSocketRequest{body, None{}}
    case Some{+value}: cachedWebSocketBody(body, value, getCachedWebSocketInputDelta(body, value))

# WebSocket messages use the same Codex mapping and Responses fold as SSE.
# The connection is affine; no shared callbacks conceal its ownership.
type WebSocketError is Data:
  TransportFailure{message: String}
  ProtocolFailure{message: String}

type WebSocketSource<-Reason: Data, -G: Data> is Type:
  WebSocketSource{connection: Socket.Connection<Deadline.Cause<Reason>>, controller: Abort.AbortController<Deadline.Cause<Reason>>, parent: Signal(Reason), idle: Maybe<&2, U32>, events: EventStream(G), initial: T.AssistantMessage<V.Value, G>, started: Bool, ended: Bool, turn: Maybe<&2, Bool>}

def WebSocketStep(-Reason: Data, -G: Data) -> Type: WebSocketSource<Reason, G> & Result<&2, &2, WebSocketError, Maybe<&2, Stream.ResponseStreamEvent>>

type WebSocketPhase<-Reason: Data, -G: Data> is Type:
  SocketReading{source: WebSocketSource<Reason, G>}
  SocketMapping{source: WebSocketSource<Reason, G>, mapped: Mapped}
  SocketReceived{source: WebSocketSource<Reason, G>, result: Result<&2, &2, String, WS.Message>}

def webSocketMapped(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Mapped:
  match result:
    case Done{value}: mapValue(value)
    case Fail{cause}: Thrown{"Invalid Codex WebSocket JSON: " ++ parseErrorText(cause)}

def socketFailure(-Reason: Data, -G: Data, source: WebSocketSource<Reason, G>, error: WebSocketError) -> IO(WebSocketStep(Reason, G)):
  IO.pure(WebSocketStep(Reason, G), (source, Fail{error}))

def socketStarted(-G: Data, events: EventStream(G), initial: T.AssistantMessage<V.Value, G>, started: Bool) -> IO(Unit):
  match started:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, T.Start{initial})

def socketYield(-Reason: Data, -G: Data, source: WebSocketSource<Reason, G>, event: Stream.ResponseStreamEvent, ended: Bool, turn: Maybe<&2, Bool>) -> IO(WebSocketStep(Reason, G)):
  match source:
    case WebSocketSource{connection, controller, parent, idle, +events, +initial, started, _, previous}:
      do IO<WebSocketStep(Reason, G)>:
        socketStarted(G, events, initial, started)
        return (WebSocketSource{connection, controller, parent, idle, events, initial, True{}, ended, mergedTurn(turn, previous)}, Done{Some{event}})

def socketReadOutcome(-Reason: Data, milliseconds: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>, pair: Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>) -> Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>:
  match pair reason:
    case (connection, result) None{}: (connection, result)
    case (connection, _) Some{Abort.Supplied{Deadline.Expired{}}}: (connection, Fail{"WebSocket idle timeout after " ++ U32.show(milliseconds) ++ "ms"})
    case (connection, _) _: (connection, Fail{aborted()})

def timedSocketWait(~Reason: Data, connection: Socket.Connection<Deadline.Cause<Reason>>, +controller: Abort.AbortController<Deadline.Cause<Reason>>, milliseconds: U32, timer: Timer & TimerCancel) -> IO(Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>):
  match timer:
    case (owner, handle):
      do IO<Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>>:
        worker : Chan(Unit) <- IO.fork(Unit, Deadline.watchTimer(Reason, controller, owner))
        pair : Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message> <- Socket.recv(~(Deadline.Cause<Reason>), connection)
        cancelled : Bool <- Timer.cancel(handle)
        IO.join(Unit, worker)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, Abort.signal(Deadline.Cause<Reason>, controller))
        return socketReadOutcome(Reason, milliseconds, reason, pair)

def timedSocketRead(~Reason: Data, connection: Socket.Connection<Deadline.Cause<Reason>>, controller: Abort.AbortController<Deadline.Cause<Reason>>, timeout: Maybe<&2, U32>) -> IO(Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>):
  match timeout:
    case None{}: Socket.recv(~(Deadline.Cause<Reason>), connection)
    case Some{0}: Socket.recv(~(Deadline.Cause<Reason>), connection)
    case Some{+milliseconds}:
      do IO<Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>>:
        timer : Timer & TimerCancel <- Timer.new(milliseconds)
        timedSocketWait(~Reason, connection, controller, milliseconds, timer)

def socketReadPhase(-Reason: Data, -G: Data, controller: Abort.AbortController<Deadline.Cause<Reason>>, parent: Signal(Reason), idle: Maybe<&2, U32>, events: EventStream(G), initial: T.AssistantMessage<V.Value, G>, started: Bool, turn: Maybe<&2, Bool>, pair: Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message>) -> WebSocketPhase<Reason, G>:
  match pair:
    case (connection, result): SocketReceived{WebSocketSource{connection, controller, parent, idle, events, initial, started, False{}, turn}, result}

def socketPonged(-Reason: Data, -G: Data, controller: Abort.AbortController<Deadline.Cause<Reason>>, parent: Signal(Reason), idle: Maybe<&2, U32>, events: EventStream(G), initial: T.AssistantMessage<V.Value, G>, started: Bool, turn: Maybe<&2, Bool>, pair: Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, Unit>) -> WebSocketPhase<Reason, G>:
  match pair:
    case (connection, Done{_}): SocketReading{WebSocketSource{connection, controller, parent, idle, events, initial, started, False{}, turn}}
    case (connection, Fail{message}): SocketReceived{WebSocketSource{connection, controller, parent, idle, events, initial, started, False{}, turn}, Fail{message}}

def binarySocketPayload(value: Result<&2, &2, UTF8.Error, String>) -> Mapped:
  match value:
    case Fail{_}: Thrown{"Invalid Codex WebSocket UTF-8"}
    case Done{payload}: webSocketMapped(Parse.parse(payload))

@unsafe
def socketAdvance(~Reason: Data, ~G: Data, phase: WebSocketPhase<Reason, G>) -> IO(WebSocketStep(Reason, G)):
  match phase:
    case SocketReading{WebSocketSource{connection, controller, parent, idle, events, initial, started, True{}, turn}}:
      IO.pure(WebSocketStep(Reason, G), (WebSocketSource{connection, controller, parent, idle, events, initial, started, True{}, turn}, Done{None{}}))
    case SocketReading{WebSocketSource{connection, +controller, +parent, +idle, events, initial, started, False{}, turn}}:
      do IO<WebSocketStep(Reason, G)>:
        pair : Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, WS.Message> <- timedSocketRead(~Reason, connection, controller, idle)
        socketAdvance(~Reason, ~G, socketReadPhase(Reason, G, controller, parent, idle, events, initial, started, turn, pair))
    case SocketMapping{source, Skip{}}: socketAdvance(~Reason, ~G, SocketReading{source})
    case SocketMapping{source, Thrown{message}}: socketFailure(Reason, G, source, ProtocolFailure{message})
    case SocketMapping{source, Pass{event}}: socketYield(Reason, G, source, event, False{}, None{})
    case SocketMapping{source, Final{event, turn}}: socketYield(Reason, G, source, event, True{}, turn)
    case SocketReceived{source, Fail{message}}: socketFailure(Reason, G, source, TransportFailure{message})
    case SocketReceived{source, Done{WS.TextMessage{SNil{}}}}: socketAdvance(~Reason, ~G, SocketReading{source})
    case SocketReceived{source, Done{WS.TextMessage{payload}}}: socketAdvance(~Reason, ~G, SocketMapping{source, webSocketMapped(Parse.parse(payload))})
    case SocketReceived{source, Done{WS.BinaryMessage{bytes}}}: socketAdvance(~Reason, ~G, SocketMapping{source, binarySocketPayload(UTF8.decodeStrict(bytes))})
    case SocketReceived{WebSocketSource{connection, controller, parent, idle, events, initial, started, ended, turn}, Done{WS.Ping{bytes}}}:
      do IO<WebSocketStep(Reason, G)>:
        pair : Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, Unit> <- Socket.sendPong(~(Deadline.Cause<Reason>), connection, bytes)
        socketAdvance(~Reason, ~G, socketPonged(Reason, G, controller, parent, idle, events, initial, started, turn, pair))
    case SocketReceived{source, Done{WS.Pong{_}}}: socketAdvance(~Reason, ~G, SocketReading{source})
    case SocketReceived{source, Done{WS.CloseMessage{_, +reason}}}: socketFailure(Reason, G, source, TransportFailure{"WebSocket stream closed before response.completed" ++ Bool.pick(String, String.is_empty(reason), "", ": " ++ reason)})

def socketChecked(~Reason: Data, ~G: Data, source: WebSocketSource<Reason, G>, cancelled: Bool) -> IO(WebSocketStep(Reason, G)):
  match cancelled:
    case True{}: socketFailure(Reason, G, source, TransportFailure{aborted()})
    case False{}: socketAdvance(~Reason, ~G, SocketReading{source})

def socketNext(~Reason: Data, ~G: Data, source: WebSocketSource<Reason, G>) -> IO(WebSocketStep(Reason, G)):
  match source:
    case WebSocketSource{connection, controller, +parent, idle, events, initial, started, ended, turn}:
      do IO<WebSocketStep(Reason, G)>:
        cancelled : Bool <- Abort.aborted(Reason, parent)
        socketChecked(~Reason, ~G, WebSocketSource{connection, controller, parent, idle, events, initial, started, ended, turn}, cancelled)

def socketClose(-Reason: Data, -G: Data, source: WebSocketSource<Reason, G>) -> IO(WebSocketSource<Reason, G> & Result<&2, &2, WebSocketError, Unit>):
  IO.pure(WebSocketSource<Reason, G> & Result<&2, &2, WebSocketError, Unit>, (source, Done{Unit{}}))

def socketEmit(-Reason: Data, -G: Data, source: WebSocketSource<Reason, G>, event: T.AssistantMessageEvent<V.Value, G>) -> IO(WebSocketSource<Reason, G> & Result<&2, &2, WebSocketError, Unit>):
  match source:
    case WebSocketSource{connection, controller, parent, idle, +events, initial, started, ended, turn}:
      do IO<WebSocketSource<Reason, G> & Result<&2, &2, WebSocketError, Unit>>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, event)
        return (WebSocketSource{connection, controller, parent, idle, events, initial, started, ended, turn}, Done{Unit{}})

# The request
# -----------
def failureOutcome(-Reason: Data, -G: Data, -E: Data, output: T.AssistantMessage<V.Value, G>, failure: Failure<E>) -> Responses.Outcome<Reason, G, E>:
  match failure:
    case Message{text}: Responses.Outcome{output, Some{Responses.OutputFailure{text}}, None{}}
    case DelayExceeded{text}: Responses.Outcome{output, Some{Responses.OutputFailure{text}}, None{}}
    case HookError{cause}: Responses.Outcome{output, Some{Responses.HookFailure{cause}}, None{}}
    case Cancelled{}: Responses.Outcome{output, Some{Responses.RequestAborted{}}, None{}}

def acquiredBody(~Reason: Data, ~G: Data, ~E: Data, +model: T.Model<J()>, options: Stream.OpenAIResponsesStreamOptions, +output: T.AssistantMessage<V.Value, G>, +events: EventStream(G), parent: Signal(Reason), acquisition: Acquisition(Reason, E)) -> IO(Responses.Outcome<Reason, G, E>):
  match acquisition:
    case Fail{failure}: IO.pure(Responses.Outcome<Reason, G, E>, failureOutcome(Reason, G, E, output, failure))
    case Done{response}:
      do IO<Responses.Outcome<Reason, G, E>>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, T.Start{output})
        streamBody(~Reason, ~G, ~E, model, options, output, events, parent, response)

type Plan<-Reason: Data, -E: Data> is Data:
  Plan{hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, timeout: Maybe<&2, U32>, retries: Nat, maxRetryDelayMs: Maybe<&2, F64>, processing: Stream.OpenAIResponsesStreamOptions}

def transportedWith(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, +model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, timeout: Maybe<&2, U32>, retries: Nat, delay: Maybe<&2, F64>, limit: Nat, processing: Stream.OpenAIResponsesStreamOptions, request: Client.Request, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), pair: Responses.Transport<Reason> & Fetch.Fetch(Reason)) -> IO(Responses.Outcome<Reason, G, E>):
  match pair:
    case (owner, fetch):
      do IO<Responses.Outcome<Reason, G, E>>:
        acquisition : Acquisition(Reason, E) <- attempts(~Reason, ~E, ~render, Context{model, hook, request, parent, fetch, timeout, delay, limit}, Start{0n, retries})
        outcome : Responses.Outcome<Reason, G, E> <- acquiredBody(~Reason, ~G, ~E, model, processing, output, events, parent, acquisition)
        Responses.retireTransport(Reason, owner)
        return outcome

def transported(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Responses.Config, +model: T.Model<J()>, plan: Plan<Reason, E>, request: Client.Request, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), opened: Result<&2, &1, Responses.Error<Reason, E>, Responses.Transport<Reason>>) -> IO(Responses.Outcome<Reason, G, E>):
  match config plan opened:
    case _ _ Fail{cause}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{cause}, None{}})
    case Responses.Config{_, _, _, _, _, limit, _} Plan{hook, timeout, retries, delay, processing} Done{transport}:
      transportedWith(~Reason, ~G, ~E, ~render, model, hook, timeout, retries, delay, limit, processing, request, output, events, parent, Responses.transportFetch(Reason, transport))

def requested(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, +config: Responses.Config, +model: T.Model<J()>, plan: Plan<Reason, E>, custom: Maybe<&2, Fetch.Fetch(Reason)>, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), request: Result<&2, &2, Client.RequestError, Client.Request>) -> IO(Responses.Outcome<Reason, G, E>):
  match request:
    case Fail{cause}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.RequestRejected{cause}}, None{}})
    case Done{wire}:
      do IO<Responses.Outcome<Reason, G, E>>:
        opened : Result<&2, &1, Responses.Error<Reason, E>, Responses.Transport<Reason>> <- Responses.openTransport(~Reason, ~E, config, custom)
        transported(~Reason, ~G, ~E, ~render, config, model, plan, wire, output, events, parent, opened)

# upstream normalizeTimeoutMs: floored; negative or non-finite is an error.
def timeoutWith(+value: F64, valid: Bool) -> Result<&2, &2, String, Maybe<&2, U32>>:
  match valid:
    case False{}: Fail{"Invalid timeoutMs: " ++ numberText(value)}
    case True{}: Done{Some{sleepMilliseconds(Timer.milliseconds(value))}}

def normalizeTimeoutMs(value: Maybe<&2, F64>) -> Result<&2, &2, String, Maybe<&2, U32>>:
  match value:
    case None{}: Done{None{}}
    case Some{+milliseconds}: timeoutWith(milliseconds, finite(milliseconds) && F.isAtLeast(F.compare(milliseconds, F.fromU32(0))))

def retriesOf(value: Maybe<&2, F64>) -> Nat:
  match value:
    case None{}: DEFAULT_MAX_RETRIES()
    case Some{count}: U32.to_nat(sleepMilliseconds(Timer.milliseconds(count)))

def codexWire(config: Responses.Config, apiKey: String, accountId: String, headers: T.ProviderHeaders(), sessionId: Maybe<&2, String>, baseUrl: String, body: J()) -> IO(Result<&2, &2, Client.RequestError, Client.Request>):
  match config:
    case Responses.Config{url, defaults, _, _, _, _, _}: IO.pure(Result<&2, &2, Client.RequestError, Client.Request>, Client.prepareCodexRequest(url, defaults, apiKey, accountId, headers, sessionId, baseUrl, None{}, body))

# WebSocket acquisition and fallback share the immutable prepared HTTP request.
# SSE receives the original headers/body, unaffected by the upgrade overlays.
type WebSocketAttempt<-Reason: Data, -G: Data, -E: Data> is Data:
  WebSocketAttempt{outcome: Responses.Outcome<Reason, G, E>, fallback: Bool}

def socketErrorMessage(error: WebSocketError) -> String:
  match error:
    case TransportFailure{message}: message
    case ProtocolFailure{message}: message

def socketCanFallback(started: Bool, error: Maybe<&2, Stream.Error<WebSocketError>>) -> Bool:
  match started error:
    case False{} Some{Stream.ReadFailure{TransportFailure{_}}}: True{}
    case _ _: False{}

def socketProcessingMessage(error: Stream.Error<WebSocketError>) -> String:
  match error:
    case Stream.ReadFailure{cause}: socketErrorMessage(cause)
    case Stream.EmitFailure{cause}: socketErrorMessage(cause)
    case Stream.ContentFailure{cause}: Sampling.errorMessage(cause)
    case Stream.TerminalFailure{cause}: Stream.terminalMessage(cause)

def socketFinished(-Reason: Data, -G: Data, -E: Data, pair: WebSocketSource<Reason, G> & Stream.RunResult<G, WebSocketError>) -> IO(WebSocketAttempt<Reason, G, E>):
  match pair:
    case (WebSocketSource{connection, _, _, _, _, _, started, _, turn}, Stream.RunResult{output, +error}):
      do IO<WebSocketAttempt<Reason, G, E>>:
        Socket.dispose(Deadline.Cause<Reason>, connection)
        return WebSocketAttempt{Responses.Outcome{withEndTurn(G, output, turn), Maybe.map(&2, Stream.Error<WebSocketError>, Responses.Error<Reason, E>, cause => Responses.OutputFailure{socketProcessingMessage(cause)}, error), None{}}, socketCanFallback(started, error)}

def socketSent(~Reason: Data, ~G: Data, ~E: Data, model: T.Model<J()>, processing: Stream.OpenAIResponsesStreamOptions, +output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), controller: Abort.AbortController<Deadline.Cause<Reason>>, idle: Maybe<&2, U32>, pair: Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, Unit>) -> IO(WebSocketAttempt<Reason, G, E>):
  match pair:
    case (connection, Fail{message}):
      do IO<WebSocketAttempt<Reason, G, E>>:
        Socket.dispose(Deadline.Cause<Reason>, connection)
        return WebSocketAttempt{Responses.Outcome{output, Some{Responses.OutputFailure{message}}, None{}}, True{}}
    case (connection, Done{_}):
      do IO<WebSocketAttempt<Reason, G, E>>:
        pair : WebSocketSource<Reason, G> & Stream.RunResult<G, WebSocketError> <- Stream.processResponsesStream(~WebSocketSource<Reason, G>, ~WebSocketError, ~J(), ~G, ~(socketNext(~Reason, ~G)), ~(socketClose(Reason, G)), ~(socketEmit(Reason, G)), ~Responses.resolveCodexServiceTier, ~Responses.tierPricing, WebSocketSource{connection, controller, parent, idle, events, output, False{}, False{}, None{}}, output, model, processing)
        socketFinished(Reason, G, E, pair)

def socketWithScope(~Reason: Data, ~G: Data, ~E: Data, model: T.Model<J()>, processing: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), scope: Deadline.Scope<Reason>, idle: Maybe<&2, U32>, sent: Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, Unit>) -> IO(WebSocketAttempt<Reason, G, E>):
  match scope:
    case Deadline.Scope{+controller, lifetime}:
      do IO<WebSocketAttempt<Reason, G, E>>:
        outcome : WebSocketAttempt<Reason, G, E> <- socketSent(~Reason, ~G, ~E, model, processing, output, events, parent, controller, idle, sent)
        ignored : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, Deadline.Scope{controller, lifetime})
        return outcome

def socketConnected(~Reason: Data, ~G: Data, ~E: Data, model: T.Model<J()>, processing: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), scope: Deadline.Scope<Reason>, idle: Maybe<&2, U32>, body: Result<&2, &2, String, String>, result: Result<&2, &1, String, Socket.Connection<Deadline.Cause<Reason>>>) -> IO(WebSocketAttempt<Reason, G, E>):
  match result body:
    case Fail{message} _:
      do IO<WebSocketAttempt<Reason, G, E>>:
        ignored : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return WebSocketAttempt{Responses.Outcome{output, Some{Responses.OutputFailure{message}}, None{}}, True{}}
    case Done{connection} Fail{message}:
      do IO<WebSocketAttempt<Reason, G, E>>:
        Socket.dispose(Deadline.Cause<Reason>, connection)
        ignored : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return WebSocketAttempt{Responses.Outcome{output, Some{Responses.OutputFailure{message}}, None{}}, False{}}
    case Done{connection} Done{text}:
      do IO<WebSocketAttempt<Reason, G, E>>:
        following : Deadline.Scope<Reason> <- Deadline.disarm(Reason, scope)
        sent : Socket.Connection<Deadline.Cause<Reason>> & Result<&2, &2, String, Unit> <- Socket.sendText(~(Deadline.Cause<Reason>), connection, text)
        socketWithScope(~Reason, ~G, ~E, model, processing, output, events, parent, following, idle, sent)

def socketDeadline(-Reason: Data, parent: Signal(Reason), timeout: Maybe<&2, U32>) -> IO(Deadline.Scope<Reason>):
  match timeout:
    case Some{0}: Deadline.follow(Reason, parent)
    case Some{milliseconds}: Deadline.create(Reason, milliseconds, parent)
    case None{}: Deadline.create(Reason, 15000, parent)

def webSocketAddress(value: String) -> String:
  match value:
    case SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{':', rest}}}}}: "ws:" ++ rest
    case SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{'s', SCon{':', rest}}}}}}: "wss:" ++ rest
    case other: other

def responseCreateParsed(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Result<&2, &2, String, String>:
  match result:
    case Done{V.ObjectValue{+fields}}:
      +kind = Maybe.default(&2, V.Value, R.get(V.Value, fields, "type"), V.Text{"response.create"})
      Done{Maybe.default(&2, String, Wire.stringify(Schema.toJson(V.ObjectValue{R.set(V.Value, fields, "type", kind)})), "")}
    case _: Fail{"Codex WebSocket request must be a JSON object"}

def responseCreate(body: String) -> Result<&2, &2, String, String>: responseCreateParsed(Parse.parse(body))

def socketOpen(~Reason: Data, ~G: Data, ~E: Data, +model: T.Model<J()>, processing: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), idle: Maybe<&2, U32>, runtime: Fetch.Runtime, config: Socket.Config, url: String, headers: H.Headers, body: String, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(WebSocketAttempt<Reason, G, E>):
  match pair:
    case (scope, signal):
      do IO<WebSocketAttempt<Reason, G, E>>:
        connected : Result<&2, &1, String, Socket.Connection<Deadline.Cause<Reason>>> <- Socket.connect(~(Deadline.Cause<Reason>), config, url, headers, signal)
        attempt : WebSocketAttempt<Reason, G, E> <- socketConnected(~Reason, ~G, ~E, model, processing, output, events, parent, scope, idle, responseCreate(body), connected)
        Fetch.dispose(runtime)
        return attempt

def socketBorrowed(~Reason: Data, ~G: Data, ~E: Data, +model: T.Model<J()>, processing: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), timeout: Maybe<&2, U32>, idle: Maybe<&2, U32>, request: Client.Request, pair: Fetch.Runtime & Socket.Config) -> IO(WebSocketAttempt<Reason, G, E>):
  match request pair:
    case Client.Request{url, _, +headers, body, _} Tuple{runtime, config}:
      do IO<WebSocketAttempt<Reason, G, E>>:
        scope : Deadline.Scope<Reason> <- socketDeadline(Reason, parent, timeout)
        socketOpen(~Reason, ~G, ~E, model, processing, output, events, parent, idle, runtime, config, webSocketAddress(URL.serialize(url, True{})), Result.default(&2, &2, H.HeaderSyntaxError, H.Headers, H.delete(headers, "OpenAI-Beta"), headers), body, Deadline.borrow(Reason, scope))

def socketRuntime(~Reason: Data, ~G: Data, ~E: Data, config: Responses.Config, model: T.Model<J()>, processing: Stream.OpenAIResponsesStreamOptions, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), timeout: Maybe<&2, U32>, idle: Maybe<&2, U32>, request: Client.Request, runtime: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(WebSocketAttempt<Reason, G, E>):
  match config runtime:
    case _ Fail{_}: IO.pure(WebSocketAttempt<Reason, G, E>, WebSocketAttempt{Responses.Outcome{output, Some{Responses.OutputFailure{"WebSocket resolver initialization failed"}}, None{}}, True{}})
    case Responses.Config{url, _, _, _, security, _, _} Done{runtime}: socketBorrowed(~Reason, ~G, ~E, model, processing, output, events, parent, timeout, idle, request, Socket.borrow(runtime, security, url))

def socketFallback(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Responses.Config, model: T.Model<J()>, plan: Plan<Reason, E>, custom: Maybe<&2, Fetch.Fetch(Reason)>, original: T.AssistantMessage<V.Value, G>, events: EventStream(G), parent: Signal(Reason), request: Client.Request, attempt: WebSocketAttempt<Reason, G, E>, cancelled: Bool) -> IO(Responses.Outcome<Reason, G, E>):
  match cancelled attempt:
    case True{} WebSocketAttempt{Responses.Outcome{partial, _, _}, _}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{partial, Some{Responses.RequestAborted{}}, None{}})
    case False{} WebSocketAttempt{_, True{}}: requested(~Reason, ~G, ~E, ~render, config, model, plan, custom, original, events, parent, Done{request})
    case False{} WebSocketAttempt{outcome, False{}}: IO.pure(Responses.Outcome<Reason, G, E>, outcome)

def usesWebSocket(transport: Maybe<&2, T.Transport>) -> Bool:
  match transport:
    case Some{T.Sse{}}: False{}
    case _: True{}

def selectedSocket(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, +configuration: Responses.Config, +model: T.Model<J()>, +selection: Plan<Reason, E>, custom: Maybe<&2, Fetch.Fetch(Reason)>, +output: T.AssistantMessage<V.Value, G>, +events: EventStream(G), +parent: Signal(Reason), +wire: Client.Request, deadline: Maybe<&2, U32>) -> IO(Responses.Outcome<Reason, G, E>):
  match configuration selection:
    case Responses.Config{url, defaults, +files, +options, security, limit, synthesize} Plan{hook, idle, retries, delay, processing}:
      do IO<Responses.Outcome<Reason, G, E>>:
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(files, options)
        attempt : WebSocketAttempt<Reason, G, E> <- socketRuntime(~Reason, ~G, ~E, configuration, model, processing, output, events, parent, deadline, idle, wire, runtime)
        cancelled : Bool <- Abort.aborted(Reason, parent)
        socketFallback(~Reason, ~G, ~E, ~render, configuration, model, selection, custom, output, events, parent, wire, attempt, cancelled)

def selectedTransport(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, +configuration: Responses.Config, +model: T.Model<J()>, +selection: Plan<Reason, E>, +custom: Maybe<&2, Fetch.Fetch(Reason)>, +output: T.AssistantMessage<V.Value, G>, +events: EventStream(G), +parent: Signal(Reason), trySocket: Bool, connectDeadline: Result<&2, &2, String, Maybe<&2, U32>>, wireResult: Result<&2, &2, Client.RequestError, Client.Request>) -> IO(Responses.Outcome<Reason, G, E>):
  match trySocket wireResult connectDeadline:
    case False{} wire _: requested(~Reason, ~G, ~E, ~render, configuration, model, selection, custom, output, events, parent, wire)
    case True{} Fail{cause} _: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.RequestRejected{cause}}, None{}})
    case True{} _ Fail{message}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.OutputFailure{message}}, None{}})
    case True{} Done{+wire} Done{deadline}: selectedSocket(~Reason, ~G, ~E, ~render, configuration, model, selection, custom, output, events, parent, wire, deadline)

def timed(~Reason: Data, ~G: Data, ~E: Data, ~render: E -> String, +config: Responses.Config, +model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, processing: Stream.OpenAIResponsesStreamOptions, custom: Maybe<&2, Fetch.Fetch(Reason)>, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), request: IO(Result<&2, &2, Client.RequestError, Client.Request>), timeout: Result<&2, &2, String, Maybe<&2, U32>>, transport: Maybe<&2, T.Transport>, connectTimeout: Maybe<&2, F64>) -> IO(Responses.Outcome<Reason, G, E>):
  match timeout:
    case Fail{message}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.OutputFailure{message}}, None{}})
    case Done{deadline}:
      do IO<Responses.Outcome<Reason, G, E>>:
        wire : Result<&2, &2, Client.RequestError, Client.Request> <- request
        selectedTransport(~Reason, ~G, ~E, ~render, config, model, Plan{hook, deadline, retriesOf(retries), delay, processing}, custom, output, events, parent, usesWebSocket(transport), normalizeTimeoutMs(connectTimeout), wire)

def payloaded(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, +config: Responses.Config, +model: T.Model<J()>, options: Responses.StreamOptions(Reason, Telemetry, E), request: Responses.ProviderRequest, output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), chosen: Result<&2, &2, E, J()>) -> IO(Responses.Outcome<Reason, G, E>):
  match options request chosen:
    case _ _ Fail{cause}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.HookFailure{cause}}, None{}})
    case T.StreamOptions{_, _, _, custom, _, _, hook, _, timeout, retries, delay, _, _, _, transport, _, _, ws, _} Responses.ProviderRequest{apiKey, baseUrl, headers, _, Responses.CodexTarget{accountId, sessionId}, processing} Done{body}:
      timed(~Reason, ~G, ~E, ~render, config, model, hook, retries, delay, processing, custom, output, events, parent, codexWire(config, apiKey, accountId, headers, sessionId, baseUrl, body), normalizeTimeoutMs(timeout), transport, ws)
    case _ _ Done{_}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.PreparationFailure{Responses.UnsupportedApi{T.OpenAIResponsesApi{}}}}, None{}})

def codexRequest(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Responses.Config, +model: T.Model<J()>, +options: Responses.StreamOptions(Reason, Telemetry, E), output: T.AssistantMessage<V.Value, G>, events: EventStream(G), +parent: Signal(Reason), ready: Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>) -> IO(Responses.Outcome<Reason, G, E>):
  match options ready:
    case _ Fail{cause}: IO.pure(Responses.Outcome<Reason, G, E>, Responses.Outcome{output, Some{Responses.PreparationFailure{cause}}, None{}})
    case T.StreamOptions{_, _, _, _, _, payloadCallback, _, _, _, _, _, _, _, _, _, _, _, _, _} Done{Responses.ProviderRequest{apiKey, baseUrl, headers, +payload, target, processing}}:
      do IO<Responses.Outcome<Reason, G, E>>:
        chosen : Result<&2, &2, E, J()> <- Responses.payloadHook(E, payload, model, payloadCallback)
        payloaded(~Reason, ~Telemetry, ~G, ~E, ~render, config, model, options, Responses.ProviderRequest{apiKey, baseUrl, headers, payload, target, processing}, output, events, parent, chosen)

def produceWith(~Reason: Data, ~Telemetry: Data, ~G: Data, ~E: Data, ~render: E -> String, config: Responses.Config, +model: T.Model<J()>, options: Responses.StreamOptions(Reason, Telemetry, E), +events: EventStream(G), timestamp: F64, preparation: IO(Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest>), pair: Responses.SignalOwner<Reason> & Signal(Reason)) -> IO(Responses.RunResult<Reason, G, E>):
  match pair:
    case (owner, +parent):
      do IO<Responses.RunResult<Reason, G, E>>:
        ready : Result<&2, &2, Responses.PreparationError, Responses.ProviderRequest> <- preparation
        outcome : Responses.Outcome<Reason, G, E> <- codexRequest(~Reason, ~Telemetry, ~G, ~E, ~render, config, model, options, Responses.initialMessage(G, model, timestamp), events, parent, ready)
        cancelled : Bool <- Abort.aborted(Reason, parent)
        Responses.settled(~Reason, ~G, ~E, ~render, events, Responses.errorProvider(model), owner, IO.pure(Unit, Unit{}), cancelled, outcome)

# Entry points
# ------------

def startStream(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +config: Responses.Config, +model: T.Model<J()>, context: Responses.Context(G, D), +options: Responses.OpenAIResponsesOptions<Reason, Telemetry, E>, +base: Responses.StreamOptions(Reason, Telemetry, E)) -> IO(Responses.Run<Reason, G, E>):
  match base:
    case T.StreamOptions{requestedSignal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}:
      do IO<Responses.Run<Reason, G, E>>:
        signal : Responses.SignalOwner<Reason> <- Responses.selectSignal(Reason, requestedSignal)
        +events : EventStream(G) <- Events.createAssistantMessageEventStream(~V.Value, ~G)
        timestamp : F64 <- Date.now()
        task : Chan(Responses.RunResult<Reason, G, E>) <- IO.fork(Responses.RunResult<Reason, G, E>, produceWith(~Reason, ~Telemetry, ~G, ~E, ~render, config, model, T.StreamOptions{requestedSignal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, events, timestamp, Responses.responsesPreparation(~Reason, ~Telemetry, ~G, ~D, ~E, config, model, context, options), Responses.ownedSignal(Reason, signal)))
        return Responses.Running{events, task}

# upstream openai-codex-responses.ts `stream` over SSE.
def stream(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Responses.Config, +model: T.Model<J()>, context: Responses.Context(G, D), +options: Responses.OpenAIResponsesOptions<Reason, Telemetry, E>) -> IO(Responses.Run<Reason, G, E>):
  startStream(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, model, context, options, Responses.toStreamOptions(Reason, Telemetry, E, options))

def codexRun(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, auth: Result<&2, &2, Responses.PreparationError, Unit>, config: Responses.Config, +model: T.Model<J()>, +context: Responses.Context(G, D), +options: Maybe<&2, Responses.SimpleStreamOptions(Reason, Telemetry, E)>) -> IO(Responses.SimpleRun(Reason, G, E)):
  match auth:
    case Fail{cause}: IO.pure(Responses.SimpleRun(Reason, G, E), Fail{cause})
    case Done{_}:
      do IO<Responses.SimpleRun(Reason, G, E)>:
        owner : Responses.Run<Reason, G, E> <- stream(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, config, model, context, Responses.fromStreamOptions(Reason, Telemetry, E, Simple.buildBaseOptionsWith(~V.Value, ~V.Value, ~G, ~D, ~J(), ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, ~Schema.toJson, ~Schema.toJson, model, context, options, Responses.simpleApiKey(Reason, Telemetry, E, options)), Responses.simpleSettings(Reason, Telemetry, E, model, options)))
        return Done{owner}

# upstream streamSimple: a missing API key fails before a stream exists.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~G: Data, ~D: Data, ~E: Data, ~render: E -> String, config: Responses.Config, +model: T.Model<J()>, +context: Responses.Context(G, D), +options: Maybe<&2, Responses.SimpleStreamOptions(Reason, Telemetry, E)>) -> IO(Responses.SimpleRun(Reason, G, E)):
  codexRun(~Reason, ~Telemetry, ~G, ~D, ~E, ~render, Responses.presentKey(T.modelProvider(model), Responses.simpleApiKey(Reason, Telemetry, E, options)), config, model, context, options)
