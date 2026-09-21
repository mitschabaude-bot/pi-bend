import Base
import ../packages/ai/src/api/openai-sse-default-hooks.bend as H
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/api/openai-sse-json.bend as Json
import ../packages/runtime/src/json-parse.bend as Parse
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C

def accepted(value: Result<&2, &2, SSE.ReadError<String>, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "default diagnostic rejected")

def call(report: C.Callback<Json.Error, Result<&2, &2, SSE.ReadError<String>, Unit>>, error: Json.Error) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, SSE.ReadError<String>, Unit> <- C.call(Json.Error, Result<&2, &2, SSE.ReadError<String>, Unit>, report, error)
    accepted(result)

def parentLive(aborted: Bool) -> IO(Unit):
  match aborted:
    case False{}: IO.print("caller:live")
    case True{}: IO.die(Unit, 1, "default hook aborted caller")

def exercise(pair: H.Owner<String> & SSE.Hooks<String>) -> IO(Unit):
  match pair:
    case Tuple{owner, SSE.Hooks{+cancel, +report}}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        C.call(Unit, Unit, cancel, Unit{})
        call(report, Json.InvalidJson{Parse.UnexpectedToken{}, "{broken", ": current" <> "data: {broken" <> Nil{}, Json.ClientLogger{}})
        call(report, Json.InvalidJson{Parse.UnexpectedEnd{}, "héllo\n😀", "data: héllo" <> "data: 😀" <> "quote: \"\\\t" <> Nil{}, Json.ConsoleLogger{}})
        call(report, Json.InvalidJson{Parse.InvalidValue{}, "", Nil{}, Json.ClientLogger{}})
        call(report, Json.ApiErrorPayload{V.Null{}})
        C.call(Unit, Unit, cancel, Unit{})
        H.dispose(String, owner)
        live : Bool <- Abort.aborted(String, Abort.signal(String, parent))
        parentLive(live)
        Abort.dispose(String, parent)

def repeat(count: Nat) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        owner : H.Owner<String> <- H.create(~String)
        exercise(H.borrow(String, owner))
        repeat(rest)

def main() -> IO(Unit): repeat(8n)
