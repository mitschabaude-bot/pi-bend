import Base
import ./json.bend as J
import ./native.bend as N
import ./util.bend as U
import ./sse.bend as S
import ./auth.bend as A

type EventKind is Data:
  TextDelta{}
  Completed{}
  Failed{}
  Other{}

type Outcome is Data:
  Outcome{response: J.Json, error: String, completed: Bool}

type Scan is Data:
  Scan{parser: S.State, outcome: Outcome}

def event_kind(+kind: String) -> EventKind:
  Bool.pick(EventKind, String.eq(kind, "response.output_text.delta"), TextDelta{}, Bool.pick(EventKind, String.eq(kind, "response.completed") || String.eq(kind, "response.done"), Completed{}, Bool.pick(EventKind, String.eq(kind, "error") || String.eq(kind, "response.failed") || String.eq(kind, "protocol_error") || String.eq(kind, "response.incomplete"), Failed{}, Other{})))

def handle_event(kind: EventKind, +event: J.Json, out: Outcome) -> IO(Outcome):
  match kind:
    case TextDelta{}:
      do IO<Outcome>:
        IO.write(U.field(event, "delta"))
        return out
    case Completed{}: IO.pure(Outcome, Outcome{J.get(event, "response"), "", True{}})
    case Failed{}: IO.pure(Outcome, Outcome{J.Null{}, "Provider stream failed: " ++ J.encode(event), False{}})
    case Other{}: IO.pure(Outcome, out)

def events(xs: J.Json, out: Outcome) -> IO(Outcome):
  match xs:
    case J.Item{+event, rest}:
      do IO<Outcome>:
        next : Outcome <- handle_event(event_kind(U.field(event, "type")), event, out)
        events(rest, next)
    case _: IO.pure(Outcome, out)

def consume(state: S.State, out: Outcome) -> IO(Scan):
  match state:
    case S.State{line, data, xs}:
      do IO<Scan>:
        next : Outcome <- events(J.reverse(xs, J.End{}), out)
        return Scan{S.State{line, data, J.End{}}, next}

def stream_loop(fuel: Nat, chunk: Result<&1, &1, U32 & String, String>, +handle: String, scan: Scan) -> IO(Outcome):
  match fuel chunk scan:
    case 0n _ _: IO.pure(Outcome, Outcome{J.Null{}, "Provider stream chunk limit exceeded", False{}})
    case 1n+n Fail{(code, message)} _: IO.pure(Outcome, Outcome{J.Null{}, message, False{}})
    case 1n+n Done{SNil{}} Scan{parser, out}: IO.pure(Outcome, out)
    case 1n+n Done{SCon{c, t}} Scan{parser, out}:
      do IO<Outcome>:
        next : Scan <- consume(S.feed(SCon{c, t}, parser), out)
        chunk : Result<&1, &1, U32 & String, String> <- N.next(handle)
        stream_loop(n, chunk, handle, next)

def finish_outcome(out: Outcome, status: String) -> IO(J.Json):
  match out:
    case Outcome{response, SNil{}, True{}}: IO.pure(J.Json, response)
    case Outcome{_, SNil{}, False{}}: IO.die(J.Json, 1, "Provider stream ended without a completion event (HTTP " ++ status ++ ")")
    case Outcome{_, error, _}: IO.die(J.Json, 1, error)

def receive(+handle: String) -> IO(J.Json):
  do IO<J.Json>:
    first : Result<&1, &1, U32 & String, String> <- N.next(handle)
    out : Outcome <- stream_loop(U32.to_nat(1048576), first, handle, Scan{S.empty(), Outcome{J.Null{}, "", False{}}})
    status : String <- N.status(handle)
    closed : String <- N.close(handle)
    finish_outcome(out, status)

def request_body(model: String, instructions: String, input: J.Json, tools: J.Json, session: String, effort: String) -> J.Json:
  base = J.str_field("model", model, J.str_field("instructions", instructions, J.str_field("prompt_cache_key", session, J.End{})))
  flags = {J.Field{"store", J.Boolean{False{}}, J.Field{"stream", J.Boolean{True{}}, J.Field{"parallel_tool_calls", J.Boolean{True{}}, base}}} : J.Json}
  text = {J.Field{"text", J.Object{J.str_field("verbosity", "low", J.End{})}, J.Field{"reasoning", J.Object{J.str_field("effort", effort, J.str_field("summary", "auto", J.End{}))}, flags}} : J.Json}
  include = {J.Field{"include", J.Array{J.Item{J.Text{"reasoning.encrypted_content"}, J.End{}}}, text} : J.Json}
  J.Object{J.Field{"input", J.Array{input}, J.Field{"tools", J.Array{tools}, include}}}

def call(auth: A.Credential, +session: String, model: String, instructions: String, input: J.Json, tools: J.Json, effort: String) -> IO(J.Json):
  do IO<J.Json>:
    handle : String <- N.http("https://chatgpt.com/backend-api/codex/responses", A.headers(auth, session), J.encode(request_body(model, instructions, input, tools, session, effort)), U32.to_nat(600000))
    receive(handle)

def user_message(text: String) -> J.Json:
  J.Object{J.str_field("role", "user", J.str_field("content", text, J.End{}))}
