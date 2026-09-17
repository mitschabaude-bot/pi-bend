import Base
import ./json.bend as J

type State is Data:
  State{line: String, data: String, events: J.Json}

def event_result(r: Result<&2, &2, String, J.Json>) -> J.Json:
  match r:
    case Done{j}: j
    case Fail{e}: J.Object{J.str_field("type", "protocol_error", J.str_field("message", e, J.End{}))}

def dispatch(+data: String, +events: J.Json) -> J.Json:
  Bool.pick(J.Json, String.is_empty(data) || String.eq(String.trim(data), "[DONE]"), events, J.Item{event_result(J.parse(data)), events})

def append_data(is_data: Bool, line: String, data: String, events: J.Json) -> State:
  match is_data:
    case False{}: State{"", data, events}
    case True{}: State{"", data ++ line ++ "\n", events}

def strip_space(+s: String) -> String:
  match s:
    case SCon{' ', t}: t
    case _: s

def line_done(line: String, data: String, events: J.Json) -> State:
  match line:
    case SNil{}: State{"", "", dispatch(data, events)}
    case SCon{+c, +t}:
      +line = {SCon{c, t} : String}
      append_data(String.starts_with(line, "data:"), strip_space(String.drop(line, 5n)), data, events)

def step(+c: U32, state: State) -> State:
  match c state:
    case 10 State{line, data, events}: line_done(String.reverse(line), data, events)
    case 13 state: state
    case _ State{line, data, events}: State{SCon{Chr{c}, line}, data, events}

def feed(s: String, state: State) -> State:
  match s:
    case SNil{}: state
    case SCon{c, t}: feed(t, step(Char.to_u32(c), state))

def empty() -> State: State{"", "", J.End{}}
