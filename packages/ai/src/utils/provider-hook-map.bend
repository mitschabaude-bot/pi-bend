import Base
import ../types.bend as T
import ../../../runtime/src/callback.bend as C

# Provider wrappers own these adapters, never the caller's original hooks.
# Payload replacement remains optional; explicit null is a payload value.
type Hooks<-Value: Data, -Model: Data, -E: Data> is Data:
  Hooks{payload: Maybe<&2, T.PayloadCallback(Value, Model, E)>, response: Maybe<&2, T.ResponseCallback(Model, E)>}

type Owner<-Value: Data, -Model: Data, -E: Data> is Type:
  Owner{hooks: Hooks<Value, Model, E>}

def result(-Source: Data, -Target: Data, -Value: Data, embed: Source -> Target, value: Result<&2, &2, Source, Value>) -> Result<&2, &2, Target, Value>:
  match value:
    case Done{output}: Done{output}
    case Fail{cause}: Fail{embed(cause)}

def invoke(~Input: Data, ~Value: Data, ~Source: Data, ~Target: Data, ~embed: Source -> Target, original: C.Callback<Input, Result<&2, &2, Source, Value>>, input: Input) -> IO(Result<&2, &2, Target, Value>):
  do IO<Result<&2, &2, Target, Value>>:
    output : Result<&2, &2, Source, Value> <- C.call(Input, Result<&2, &2, Source, Value>, original, input)
    return result(Source, Target, Value, embed, output)

def adapter(~Input: Data, ~Value: Data, ~Source: Data, ~Target: Data, ~embed: Source -> Target, original: Maybe<&2, C.Callback<Input, Result<&2, &2, Source, Value>>>) -> IO(Maybe<&2, C.Callback<Input, Result<&2, &2, Target, Value>>>):
  match original:
    case None{}: IO.pure(Maybe<&2, C.Callback<Input, Result<&2, &2, Target, Value>>>, None{})
    case Some{callback}:
      do IO<Maybe<&2, C.Callback<Input, Result<&2, &2, Target, Value>>>>:
        mapped : C.Callback<Input, Result<&2, &2, Target, Value>> <- C.create(~C.Callback<Input, Result<&2, &2, Source, Value>>, ~Input, ~Result<&2, &2, Target, Value>, ~(invoke(~Input, ~Value, ~Source, ~Target, ~embed)), callback)
        return Some{mapped}

def create(~Value: Data, ~Model: Data, ~Source: Data, ~Target: Data, ~embed: Source -> Target, hooks: Hooks<Value, Model, Source>) -> IO(Owner<Value, Model, Target>):
  match hooks:
    case Hooks{payload, response}:
      do IO<Owner<Value, Model, Target>>:
        mappedPayload : Maybe<&2, T.PayloadCallback(Value, Model, Target)> <- adapter(~T.PayloadInput<Value, Model>, ~Maybe<&2, Value>, ~Source, ~Target, ~embed, payload)
        mappedResponse : Maybe<&2, T.ResponseCallback(Model, Target)> <- adapter(~T.ResponseInput<Model>, ~Unit, ~Source, ~Target, ~embed, response)
        return Owner{Hooks{mappedPayload, mappedResponse}}

def borrow(-Value: Data, -Model: Data, -E: Data, owner: Owner<Value, Model, E>) -> Owner<Value, Model, E> & Hooks<Value, Model, E>:
  match owner:
    case Owner{+hooks}: (Owner{hooks}, hooks)

def retireOptional(-Input: Data, -Value: Data, -E: Data, callback: Maybe<&2, C.Callback<Input, Result<&2, &2, E, Value>>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: C.dispose(Input, Result<&2, &2, E, Value>, value)

def dispose(-Value: Data, -Model: Data, -E: Data, owner: Owner<Value, Model, E>) -> IO(Unit):
  match owner:
    case Owner{Hooks{payload, response}}:
      do IO<Unit>:
        retireOptional(T.PayloadInput<Value, Model>, Maybe<&2, Value>, E, payload)
        retireOptional(T.ResponseInput<Model>, Unit, E, response)
