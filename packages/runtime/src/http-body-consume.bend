import Base
import ./http-response.bend as Response
import ./http-response-progress.bend as Progress
import ./http-response-stream.bend as Stream
import ./bounded-bytes.bend as Bytes
import ./http-body-buffer.bend as Buffer
import ./utf8-strict.bend as UTF8
import ./json-parse.bend as JSON
import ./schema-value.bend as Value

def advance(-E: Data, -State: Type, buffer: Bytes.State, next: Response.Next<E, State>) -> Response.Body<State> & Buffer.Decision<E>:
  match next:
    case Response.Next{body, result}: (body, Buffer.next(E, buffer, result))

def released(-E: Data, -State: Type, result: Result<&2, &2, Buffer.PrimaryError<E>, List<&2, U32>>, next: Response.Next<E, State>) -> Result<&2, &2, Buffer.Error<E>, List<&2, U32>>:
  match next:
    case Response.Next{_, Done{_}}: Buffer.outcome(E, result, Done{Unit{}})
    case Response.Next{_, Fail{error}}: Buffer.outcome(E, result, Fail{error})

# The external transport determines termination. The explicit byte budget
# bounds retained payload; empty reads do not consume an invented fuel budget.
@unsafe def drive(-E: Data, -State: Type, +read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), +close: State -> IO(Result<&2, &2, E, Unit>), state: Response.Body<State> & Buffer.Decision<E>) -> IO(Result<&2, &2, Buffer.Error<E>, List<&2, U32>>):
  match state:
    case (body, Buffer.Finished{result}):
      do IO<Result<&2, &2, Buffer.Error<E>, List<&2, U32>>>:
        next : Response.Next<E, State> <- Response.closeWith(E, State, close, body)
        return released(E, State, result, next)
    case (body, Buffer.Continue{buffer}):
      do IO<Result<&2, &2, Buffer.Error<E>, List<&2, U32>>>:
        next : Response.Next<E, State> <- Response.nextWith(E, State, read, close, body)
        drive(E, State, read, close, advance(E, State, buffer, next))

def bytesWith(-E: Data, -State: Type, read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, body: Response.Body<State>) -> IO(Result<&2, &2, Buffer.Error<E>, List<&2, U32>>):
  drive(E, State, read, close, (body, Buffer.Continue{Bytes.create(limit)}))

type TextError<-E: Data> is Data:
  BodyFailure{error: Buffer.Error<E>}
  InvalidUTF8{error: UTF8.Error}

def textResult(-E: Data, value: Result<&2, &2, UTF8.Error, String>) -> Result<&2, &2, TextError<E>, String>:
  match value:
    case Fail{error}: Fail{InvalidUTF8{error}}
    case Done{text}: Done{text}

def decodeText(-E: Data, value: Result<&2, &2, Buffer.Error<E>, List<&2, U32>>) -> Result<&2, &2, TextError<E>, String>:
  match value:
    case Fail{error}: Fail{BodyFailure{error}}
    case Done{bytes}: textResult(E, UTF8.decode(bytes))

def textWith(-E: Data, -State: Type, read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, body: Response.Body<State>) -> IO(Result<&2, &2, TextError<E>, String>):
  do IO<Result<&2, &2, TextError<E>, String>>:
    bytes : Result<&2, &2, Buffer.Error<E>, List<&2, U32>> <- bytesWith(E, State, read, close, limit, body)
    return decodeText(E, bytes)

type JSONError<-E: Data> is Data:
  TextFailure{error: TextError<E>}
  InvalidJSON{error: JSON.Error}

def jsonResult(-E: Data, value: Result<&2, &2, JSON.Error, Value.Value>) -> Result<&2, &2, JSONError<E>, Value.Value>:
  match value:
    case Fail{error}: Fail{InvalidJSON{error}}
    case Done{json}: Done{json}

def decodeJSON(-E: Data, value: Result<&2, &2, TextError<E>, String>) -> Result<&2, &2, JSONError<E>, Value.Value>:
  match value:
    case Fail{error}: Fail{TextFailure{error}}
    case Done{text}: jsonResult(E, JSON.parse(text))

def jsonWith(-E: Data, -State: Type, read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, body: Response.Body<State>) -> IO(Result<&2, &2, JSONError<E>, Value.Value>):
  do IO<Result<&2, &2, JSONError<E>, Value.Value>>:
    text : Result<&2, &2, TextError<E>, String> <- textWith(E, State, read, close, limit, body)
    return decodeJSON(E, text)
