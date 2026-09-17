import Base
import ./json.bend as J
import ./native.bend as N
import ./util.bend as U
import ./sse.bend as S
import ./auth.bend as A

type EventKind is Data:
  TextDelta{}
  OutputDone{}
  Completed{}
  Failed{}
  Other{}

type Outcome is Data:
  Outcome{response: J.Json, error: String, completed: Bool}

type Scan is Data:
  Scan{parser: S.State, outcome: Outcome}

def event_kind(+kind: String) -> EventKind:
  Bool.pick(EventKind, String.eq(kind, "response.output_text.delta"), TextDelta{}, Bool.pick(EventKind, String.eq(kind, "response.output_item.done"), OutputDone{}, Bool.pick(EventKind, String.eq(kind, "response.completed") || String.eq(kind, "response.done"), Completed{}, Bool.pick(EventKind, String.eq(kind, "error") || String.eq(kind, "response.failed") || String.eq(kind, "protocol_error") || String.eq(kind, "response.incomplete"), Failed{}, Other{}))))

def add_item(out: Outcome, item: J.Json) -> Outcome:
  match out:
    case Outcome{+response, error, done}: Outcome{J.set(response, "output", J.Array{J.append(J.array(J.get(response, "output")), J.Item{item, J.End{}})}), error, done}

def completed_output(items: J.Json, +response: J.Json) -> J.Json:
  match items:
    case J.End{}: response
    case _: J.set(response, "output", J.Array{items})

def completed(out: Outcome, response: J.Json) -> Outcome:
  match out:
    case Outcome{prior, error, done}: Outcome{completed_output(J.array(J.get(prior, "output")), response), error, True{}}

def event_error(+event: J.Json) -> String:
  +nested = J.get(J.get(event, "response"), "error")
  +message = U.field(nested, "message")
  Bool.pick(String, String.is_empty(message), "Provider error: " ++ U.field(event, "message"), U.field(nested, "code") ++ ": " ++ message)

def text_started(out: Outcome) -> Outcome:
  match out:
    case Outcome{response, error, done}: Outcome{J.set(response, "_pi_bend_text_started", J.Boolean{True{}}), error, done}

def failed(out: Outcome, error: String) -> Outcome:
  match out:
    case Outcome{response, _, _}: Outcome{response, error, False{}}

def handle_event(kind: EventKind, +event: J.Json, out: Outcome) -> IO(Outcome):
  match kind:
    case TextDelta{}:
      do IO<Outcome>:
        IO.write(U.field(event, "delta"))
        return text_started(out)
    case OutputDone{}: IO.pure(Outcome, add_item(out, J.get(event, "item")))
    case Completed{}: IO.pure(Outcome, completed(out, J.get(event, "response")))
    case Failed{}: IO.pure(Outcome, failed(out, event_error(event)))
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

def mark_http(out: Outcome, +status: String) -> Outcome:
  match out:
    case Outcome{response, SNil{}, False{}}: Outcome{response, "Provider stream ended without completion (HTTP " ++ status ++ ")", False{}}
    case _: out

def receive_outcome(+handle: String) -> IO(Outcome):
  do IO<Outcome>:
    first : Result<&1, &1, U32 & String, String> <- N.next(handle)
    out : Outcome <- stream_loop(U32.to_nat(1048576), first, handle, Scan{S.empty(), Outcome{J.Null{}, "", False{}}})
    status : String <- N.status(handle)
    closed : String <- N.close(handle)
    return mark_http(out, status)

def retryable(out: Outcome) -> Bool:
  match out:
    case Outcome{J.Null{}, +error, False{}}: String.contains(error, "overloaded") || String.contains(error, "HTTP 429") || String.contains(error, "HTTP 500") || String.contains(error, "HTTP 502") || String.contains(error, "HTTP 503") || String.contains(error, "HTTP 504")
    case _: False{}

def attempts(fuel: Nat, again: Bool, out: Outcome, +url: String, +headers: String, +body: String, +delay: U32) -> IO(J.Json):
  match fuel again:
    case 0n _: finish_outcome(out, "unknown")
    case 1n+n False{}: finish_outcome(out, "unknown")
    case 1n+n True{}:
      do IO<J.Json>:
        IO.sleep(delay)
        handle : String <- N.http(url, headers, body, U32.to_nat(600000))
        +next : Outcome <- receive_outcome(handle)
        attempts(n, retryable(next), next, url, headers, body, Bool.pick(U32, U32.is_eq(delay, 0), 1000, (delay * 2 : U32)))

def request_body(model: String, instructions: String, input: J.Json, tools: J.Json, session: String, effort: String) -> J.Json:
  base = J.str_field("model", model, J.str_field("instructions", instructions, J.str_field("prompt_cache_key", session, J.End{})))
  flags = {J.Field{"store", J.Boolean{False{}}, J.Field{"stream", J.Boolean{True{}}, J.Field{"parallel_tool_calls", J.Boolean{True{}}, base}}} : J.Json}
  text = {J.Field{"text", J.Object{J.str_field("verbosity", "low", J.End{})}, J.Field{"reasoning", J.Object{J.str_field("effort", effort, J.str_field("summary", "auto", J.End{}))}, flags}} : J.Json}
  include = {J.Field{"include", J.Array{J.Item{J.Text{"reasoning.encrypted_content"}, J.End{}}}, text} : J.Json}
  J.Object{J.Field{"input", J.Array{input}, J.Field{"tools", J.Array{tools}, include}}}

def call(auth: A.Credential, +session: String, model: String, instructions: String, input: J.Json, tools: J.Json, effort: String) -> IO(J.Json):
  do IO<J.Json>:
    endpoint : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_BEND_RESPONSES_URL")
    attempts(4n, True{}, Outcome{J.Null{}, "No provider response", False{}}, U.either_text(endpoint, "https://chatgpt.com/backend-api/codex/responses"), A.headers(auth, session), J.encode(request_body(model, instructions, input, tools, session, effort)), 0)

def user_message(text: String) -> J.Json:
  J.Object{J.str_field("role", "user", J.str_field("content", text, J.End{}))}
