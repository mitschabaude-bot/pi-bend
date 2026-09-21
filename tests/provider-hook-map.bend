import Base
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/record.bend as Record
import ../packages/ai/src/utils/provider-hook-map.bend as Map
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R

type Error is Data:
  Hook{message: String}
type Environment is Data:
  Environment{calls: R.Ref<U32>, mode: U32, model: String}

def embed(cause: String) -> Error: Hook{cause}
def assert(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "hook adapter invariant")
def counted(calls: R.Ref<U32>) -> IO(Unit):
  do IO<Unit>:
    ignored : U32 <- R.modify(U32, U32, calls, +n => (U32.add(n, 1), n))
    return Unit{}

def payloadResult(mode: U32, text: String) -> Result<&2, &2, String, Maybe<&2, T.JsonValue>>:
  match mode:
    case 0: Done{None{}}
    case 1: Done{Some{T.JsonNull{}}}
    case 3: Fail{"payload failure"}
    case _: Done{Some{T.JsonString{text}}}

def payload(environment: Environment, input: T.PayloadInput<T.JsonValue, String>) -> IO(Result<&2, &2, String, Maybe<&2, T.JsonValue>>):
  match environment input:
    case Environment{calls, mode, model} T.PayloadInput{T.JsonString{+text}, actualModel}:
      do IO<Result<&2, &2, String, Maybe<&2, T.JsonValue>>>:
        assert(String.eq(model, actualModel))
        assert(String.eq(text, "original"))
        counted(calls)
        return payloadResult(mode, text)
    case _ _:
      IO.die(Result<&2, &2, String, Maybe<&2, T.JsonValue>>, 1, "changed hook input")

def checkedHeader(value: Maybe<&2, String>) -> IO(Unit):
  match value:
    case Some{text}: assert(String.eq(text, "retained"))
    case None{}: IO.die(Unit, 1, "lost response header")

def response(environment: Environment, input: T.ResponseInput<String>) -> IO(Result<&2, &2, String, Unit>):
  match environment input:
    case Environment{calls, mode, model} T.ResponseInput{T.ProviderResponse{status, headers}, actualModel}:
      do IO<Result<&2, &2, String, Unit>>:
        assert(String.eq(model, actualModel))
        assert(W.equal(F.toBits(status), F.toBits(F.fromU32(200))))
        checkedHeader(Record.get(String, headers, "x-provider"))
        counted(calls)
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 4), Fail{"response failure"}, Done{Unit{}})

def replacementMode(+mode: U32) -> Bool: Bool.or(U32.is_eq(mode, 2), U32.is_eq(mode, 4))

def checkPayload(mode: U32, value: Result<&2, &2, Error, Maybe<&2, T.JsonValue>>) -> IO(Unit):
  match mode value:
    case 0 Done{None{}}: IO.pure(Unit, Unit{})
    case 1 Done{Some{T.JsonNull{}}}: IO.pure(Unit, Unit{})
    case 3 Fail{Hook{text}}: assert(String.eq(text, "payload failure"))
    case other Done{Some{T.JsonString{text}}}: assert(Bool.and(String.eq(text, "original"), replacementMode(other)))
    case _ _: IO.die(Unit, 1, "changed hook result")
def checkResponse(mode: U32, value: Result<&2, &2, Error, Unit>) -> IO(Unit):
  match mode value:
    case 4 Fail{Hook{text}}: assert(String.eq(text, "response failure"))
    case other Done{_}: assert(Bool.not(U32.is_eq(other, 4)))
    case _ _: IO.die(Unit, 1, "changed response result")

def callPayload(model: String, +mode: U32, present: Bool, hook: Maybe<&2, T.PayloadCallback(T.JsonValue, String, Error)>) -> IO(Unit):
  match present hook:
    case False{} None{}: IO.pure(Unit, Unit{})
    case True{} Some{callback}:
      do IO<Unit>:
        value : Result<&2, &2, Error, Maybe<&2, T.JsonValue>> <- C.call(T.PayloadInput<T.JsonValue, String>, Result<&2, &2, Error, Maybe<&2, T.JsonValue>>, callback, T.PayloadInput{T.JsonString{"original"}, model})
        checkPayload(mode, value)
    case _ _: IO.die(Unit, 1, "hook presence changed")

def callResponse(model: String, +mode: U32, present: Bool, hook: Maybe<&2, T.ResponseCallback(String, Error)>, responseValue: T.ProviderResponse) -> IO(Unit):
  match present hook:
    case False{} None{}: IO.pure(Unit, Unit{})
    case True{} Some{callback}:
      do IO<Unit>:
        value : Result<&2, &2, Error, Unit> <- C.call(T.ResponseInput<String>, Result<&2, &2, Error, Unit>, callback, T.ResponseInput{responseValue, model})
        checkResponse(mode, value)
    case _ _: IO.die(Unit, 1, "response hook presence changed")

def invoke(+model: String, +mode: U32, hasPayload: Bool, hasResponse: Bool, responseValue: T.ProviderResponse, hooks: Map.Hooks<T.JsonValue, String, Error>) -> IO(Unit):
  match hooks:
    case Map.Hooks{payloadHook, responseHook}:
      do IO<Unit>:
        callPayload(model, mode, hasPayload, payloadHook)
        callResponse(model, mode, hasResponse, responseHook, responseValue)

def mapped(+model: String, +mode: U32, +hasPayload: Bool, +hasResponse: Bool, +responseValue: T.ProviderResponse, pair: Map.Owner<T.JsonValue, String, Error> & Map.Hooks<T.JsonValue, String, Error>) -> IO(Unit):
  match pair:
    case Tuple{owner, +hooks}:
      do IO<Unit>:
        invoke(model, mode, hasPayload, hasResponse, responseValue, hooks)
        invoke(model, mode, hasPayload, hasResponse, responseValue, hooks)
        Map.dispose(T.JsonValue, String, Error, owner)


def run(+model: String, +mode: U32, +hasPayload: Bool, +hasResponse: Bool) -> IO(Unit):
  do IO<Unit>:
    +payloadCount : R.Ref<U32> <- R.new(U32, 0)
    +responseCount : R.Ref<U32> <- R.new(U32, 0)
    +originalPayload : T.PayloadCallback(T.JsonValue, String, String) <- C.create(~Environment, ~T.PayloadInput<T.JsonValue, String>, ~Result<&2, &2, String, Maybe<&2, T.JsonValue>>, ~payload, Environment{payloadCount, mode, model})
    +originalResponse : T.ResponseCallback(String, String) <- C.create(~Environment, ~T.ResponseInput<String>, ~Result<&2, &2, String, Unit>, ~response, Environment{responseCount, mode, model})
    owner : Map.Owner<T.JsonValue, String, Error> <- Map.create(~T.JsonValue, ~String, ~String, ~Error, ~embed, Map.Hooks{Bool.pick(Maybe<&2, T.PayloadCallback(T.JsonValue, String, String)>, hasPayload, Some{originalPayload}, None{}), Bool.pick(Maybe<&2, T.ResponseCallback(String, String)>, hasResponse, Some{originalResponse}, None{})})
    +responseValue : T.ProviderResponse = T.ProviderResponse{F.fromU32(200), Record.set(String, Record.new(String), "x-provider", "retained")}
    mapped(model, mode, hasPayload, hasResponse, responseValue, Map.borrow(T.JsonValue, String, Error, owner))
    # The caller's original hooks must still work after adapter retirement.
    originalOutput : Result<&2, &2, String, Maybe<&2, T.JsonValue>> <- C.call(T.PayloadInput<T.JsonValue, String>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, originalPayload, T.PayloadInput{T.JsonString{"original"}, model})
    checkPayload(mode, Map.result(String, Error, Maybe<&2, T.JsonValue>, embed, originalOutput))
    originalStatus : Result<&2, &2, String, Unit> <- C.call(T.ResponseInput<String>, Result<&2, &2, String, Unit>, originalResponse, T.ResponseInput{responseValue, model})
    checkResponse(mode, Map.result(String, Error, Unit, embed, originalStatus))
    countPayload : U32 <- R.read(U32, payloadCount)
    countResponse : U32 <- R.read(U32, responseCount)
    assert(U32.is_eq(countPayload, Bool.pick(U32, hasPayload, 3, 1)))
    assert(U32.is_eq(countResponse, Bool.pick(U32, hasResponse, 3, 1)))
    C.dispose(T.PayloadInput<T.JsonValue, String>, Result<&2, &2, String, Maybe<&2, T.JsonValue>>, originalPayload)
    C.dispose(T.ResponseInput<String>, Result<&2, &2, String, Unit>, originalResponse)
    ignoredPayload : U32 <- R.dispose(U32, payloadCount)
    ignoredResponse : U32 <- R.dispose(U32, responseCount)
    return Unit{}

def cases(+model: String, modes: List<U32>) -> IO(Unit):
  match modes:
    case Nil{}: IO.pure(Unit, Unit{})
    case +mode <> rest:
      do IO<Unit>:
        run(model, mode, False{}, False{})
        run(model, mode, False{}, True{})
        run(model, mode, True{}, False{})
        run(model, mode, True{}, True{})
        cases(model, rest)
def main() -> IO(Unit):
  do IO<Unit>:
    cases("custom model🙂", 0 <> 1 <> 2 <> 3 <> 4 <> Nil{})
    IO.print("PASS twenty hook adapter outcomes and borrowed callback lifetimes")
