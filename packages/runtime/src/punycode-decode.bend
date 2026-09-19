import Base
import ./punycode-core.bend as Core

type Input is Data:
  Input{basic: String, encoded: String}

# Split at the final delimiter, retaining ASCII case. A leading delimiter alone
# is not a basic prefix, matching the reference decoder's invalid-input path.
def divide(reversed: String, suffix: String) -> Input:
  match reversed:
    case SNil{}: Input{"", suffix}
    case SCon{'-', SNil{}}: Input{"", SCon{'-', suffix}}
    case SCon{'-', rest}: Input{String.reverse(rest), suffix}
    case SCon{char, rest}: divide(rest, SCon{char, suffix})

type State is Data:
  State{output: List<&2, U32>, count: U32, next: U32, index: U32, bias: U32, rest: String}

def basics(text: String, reversed: List<&2, U32>, count: U32, encoded: String, valid: Bool) -> Result<&2, &2, Core.Error, State>:
  match text valid:
    case _ False{}: Fail{Core.InvalidInput{}}
    case SNil{} True{}: Done{State{List.reverse(&2, U32, reversed), count, 128, 0, 72, encoded}}
    case SCon{Chr{+code}, rest} True{}: basics(rest, code <> reversed, (count + 1 : U32), encoded, U32.is_lt(code, 128))

def prepend(reversed: List<&2, U32>, suffix: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case Nil{}: suffix
    case head <> rest: prepend(rest, head <> suffix)

def insert(parts: List<&2, U32>, index: U32, value: U32, reversed: List<&2, U32>) -> Result<&2, &2, Core.Error, List<&2, U32>>:
  match parts index:
    case parts 0: Done{prepend(reversed, value <> parts)}
    case head <> rest remaining: insert(rest, (remaining - 1 : U32), value, head <> reversed)
    case Nil{} _: Fail{Core.InvalidInput{}}

def inserted(output: Result<&2, &2, Core.Error, List<&2, U32>>, count: U32, next: U32, index: U32, bias: U32, rest: String) -> Result<&2, &2, Core.Error, State>:
  match output:
    case Fail{error}: Fail{error}
    case Done{output}: Done{State{output, count, next, (index + 1 : U32), bias, rest}}

def incremented(value: Result<&2, &2, Core.Error, U32>, output: List<&2, U32>, count: U32, +index: U32, bias: U32, rest: String) -> Result<&2, &2, Core.Error, State>:
  match value:
    case Fail{error}: Fail{error}
    case Done{+next}: inserted(insert(output, index, next, Nil{}), count, next, index, bias, rest)

def decoded(result: Result<&2, &2, Core.Error, Core.Read>, output: List<&2, U32>, +count: U32, next: U32, +previous: U32) -> Result<&2, &2, Core.Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Core.Read{+value, rest}}:
      incremented(Core.add(next, (value / count : U32)), output, count, (value % count : U32), Core.adapt((value - previous : U32), count, U32.is_eq(previous, 0)), rest)

def step(state: State) -> Result<&2, &2, Core.Error, State>:
  match state:
    case State{output, count, next, +index, bias, rest}: decoded(Core.read(rest, bias, index), output, (count + 1 : U32), next, index)

# Keep decoded points numeric until parsing finishes. This preserves overflow
# precedence while ensuring no invalid native Char can be constructed.
def scalarText(valid: Bool, point: U32, reversed: String) -> Result<&2, &2, Core.Error, String>:
  match valid:
    case False{}: Fail{Core.InvalidInput{}}
    case True{}: Done{SCon{Chr{point}, reversed}}

def text(points: List<&2, U32>, state: Result<&2, &2, Core.Error, String>) -> Result<&2, &2, Core.Error, String>:
  match points state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{String.reverse(reversed)}
    case +point <> rest Done{reversed}: text(rest, scalarText(Core.scalar(point), point, reversed))

# One iteration consumes at least one encoded ASCII character.
def loop(fuel: String, state: Result<&2, &2, Core.Error, State>) -> Result<&2, &2, Core.Error, String>:
  match fuel state:
    case _ Fail{error}: Fail{error}
    case _ Done{State{output, _, _, _, _, SNil{}}}: text(output, Done{""})
    case SNil{} _: Fail{Core.InvalidInput{}}
    case SCon{_, fuel} Done{state}: loop(fuel, step(state))

def prepared(input: Input) -> Result<&2, &2, Core.Error, String>:
  match input:
    case Input{basic, +encoded}: loop(encoded, basics(basic, Nil{}, 0, encoded, True{}))

def decode(input: String) -> Result<&2, &2, Core.Error, String>:
  prepared(divide(String.reverse(input), ""))
