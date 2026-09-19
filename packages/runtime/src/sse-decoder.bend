import Base

# Event fields from openai 6.40.0 SSEDecoder (licenses/openai-sdk.txt).
# Approved difference: empty blocks discard diagnostic-only lines.
type ServerSentEvent is Data:
  ServerSentEvent{event: Maybe<&2, String>, data: String, raw: List<&2, String>}

type SSEDecoder is Data:
  SSEDecoder{event: Maybe<&2, String>, dataReversed: List<&2, String>, rawReversed: List<&2, String>}

type Decoded is Data:
  Decoded{decoder: SSEDecoder, event: Maybe<&2, ServerSentEvent>}

type Field is Data:
  Field{name: String, value: String}

def create() -> SSEDecoder: SSEDecoder{None{}, Nil{}, Nil{}}

def dropCarriage(reversed: String) -> String:
  match reversed:
    case SCon{Chr{13}, rest}: String.reverse(rest)
    case rest: String.reverse(rest)

def dropSpace(text: String) -> String:
  match text:
    case SCon{Chr{32}, rest}: rest
    case rest: rest

def partition(text: String, reversed: String) -> Field:
  match text:
    case SNil{}: Field{String.reverse(reversed), ""}
    case SCon{Chr{58}, rest}: Field{String.reverse(reversed), dropSpace(rest)}
    case SCon{head, rest}: partition(rest, SCon{head, reversed})

def emit(event: Maybe<&2, String>, reversed: List<&2, String>, raw: List<&2, String>) -> Decoded:
  Decoded{create(), Some{ServerSentEvent{event, String.join(List.reverse(&2, String, reversed), "\n"), List.reverse(&2, String, raw)}}}

def blank(state: SSEDecoder) -> Decoded:
  match state:
    case SSEDecoder{None{}, Nil{}, _}: Decoded{create(), None{}}
    case SSEDecoder{Some{SNil{}}, Nil{}, _}: Decoded{SSEDecoder{Some{""}, Nil{}, Nil{}}, None{}}
    case SSEDecoder{event, data, raw}: emit(event, data, raw)

def field(isData: Bool, isEvent: Bool, value: String, state: SSEDecoder, line: String) -> Decoded:
  match isData isEvent state:
    case True{} _ SSEDecoder{event, data, raw}: Decoded{SSEDecoder{event, value <> data, line <> raw}, None{}}
    case _ True{} SSEDecoder{_, data, raw}: Decoded{SSEDecoder{Some{value}, data, line <> raw}, None{}}
    case _ _ SSEDecoder{event, data, raw}: Decoded{SSEDecoder{event, data, line <> raw}, None{}}

def parsed(value: Field, state: SSEDecoder, line: String) -> Decoded:
  match value:
    case Field{+name, value}: field(String.eq(name, "data"), String.eq(name, "event"), value, state, line)

def decodeLine(line: String, state: SSEDecoder) -> Decoded:
  match line:
    case SNil{}: blank(state)
    case +line: parsed(partition(line, ""), state, line)

def decode(state: SSEDecoder, line: String) -> Decoded:
  decodeLine(dropCarriage(String.reverse(line)), state)
