import Base
import ./punycode-core.bend as Core

type Basics is Data:
  Basics{count: U32, total: U32, reversed: String}

def basic(valid: Bool, ascii: Bool, code: U32, state: Basics) -> Result<&2, &2, Core.Error, Basics>:
  match valid ascii state:
    case False{} _ _: Fail{Core.InvalidInput{}}
    case True{} True{} Basics{count, total, reversed}: Done{Basics{(count + 1 : U32), (total + 1 : U32), SCon{Chr{code}, reversed}}}
    case True{} False{} Basics{count, total, reversed}: Done{Basics{count, (total + 1 : U32), reversed}}

def basics(text: String, state: Result<&2, &2, Core.Error, Basics>) -> Result<&2, &2, Core.Error, Basics>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} Done{state}: basics(rest, basic(Core.scalar(code), U32.is_lt(code, 128), code, state))

type State is Data:
  State{next: U32, delta: U32, bias: U32, handled: U32, reversed: String}

def nextCode(text: String, +floor: U32, +best: U32) -> U32:
  match text:
    case SNil{}: best
    case SCon{Chr{+code}, rest}: nextCode(rest, floor, Bool.pick(U32, U32.is_ge(code, floor), U32.min(code, best), best))

def withDelta(result: Result<&2, &2, Core.Error, U32>, next: U32, bias: U32, handled: U32, reversed: String) -> Result<&2, &2, Core.Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{delta}: Done{State{next, delta, bias, handled, reversed}}

def advanced(product: Result<&2, &2, Core.Error, U32>, delta: U32, next: U32, bias: U32, handled: U32, reversed: String) -> Result<&2, &2, Core.Error, State>:
  match product:
    case Fail{error}: Fail{error}
    case Done{product}: withDelta(Core.add(delta, product), next, bias, handled, reversed)

def advance(+next: U32, state: State) -> Result<&2, &2, Core.Error, State>:
  match state:
    case State{previous, delta, bias, +handled, reversed}: advanced(Core.multiply((next - previous : U32), (handled + 1 : U32)), delta, next, bias, handled, reversed)

def emitted(result: Result<&2, &2, Core.Error, String>, next: U32, delta: U32, +handled: U32, basics: U32) -> Result<&2, &2, Core.Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{reversed}: Done{State{next, 0, Core.adapt(delta, (handled + 1 : U32), U32.is_eq(handled, basics)), (handled + 1 : U32), reversed}}

def point(less: Bool, equal: Bool, state: State, basics: U32) -> Result<&2, &2, Core.Error, State>:
  match less equal state:
    case True{} _ State{next, delta, bias, handled, reversed}: withDelta(Core.add(delta, 1), next, bias, handled, reversed)
    case False{} True{} State{next, +delta, bias, handled, reversed}: emitted(Core.write(delta, bias, reversed), next, delta, handled, basics)
    case False{} False{} state: Done{state}

def scan(text: String, +basics: U32, state: Result<&2, &2, Core.Error, State>) -> Result<&2, &2, Core.Error, State>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} Done{State{+next, delta, bias, handled, reversed}}: scan(rest, basics, point(U32.is_lt(code, next), U32.is_eq(code, next), State{next, delta, bias, handled, reversed}, basics))

type Progress is Data:
  Active{state: State}
  Complete{output: String}

def continued(result: Result<&2, &2, Core.Error, State>) -> Result<&2, &2, Core.Error, Progress>:
  match result:
    case Fail{error}: Fail{error}
    case Done{state}: Done{Active{state}}

def checkedPass(done: Bool, state: State) -> Result<&2, &2, Core.Error, Progress>:
  match done state:
    case True{} State{_, _, _, _, reversed}: Done{Complete{String.reverse(reversed)}}
    case False{} State{next, delta, bias, handled, reversed}: continued(withDelta(Core.add(delta, 1), (next + 1 : U32), bias, handled, reversed))

def passResult(total: U32, result: Result<&2, &2, Core.Error, State>) -> Result<&2, &2, Core.Error, Progress>:
  match result:
    case Fail{error}: Fail{error}
    case Done{State{next, delta, bias, +handled, reversed}}: checkedPass(U32.is_eq(handled, total), State{next, delta, bias, handled, reversed})

def pass(+text: String, basics: U32, total: U32, state: State) -> Result<&2, &2, Core.Error, Progress>:
  match state:
    case State{+next, delta, bias, handled, reversed}: passResult(total, scan(text, basics, advance(nextCode(text, next, 1114111), State{next, delta, bias, handled, reversed})))

# Each pass emits at least one previously unhandled scalar; input length is
# therefore a structural upper bound on the number of passes.
def loop(fuel: String, +text: String, +basics: U32, +total: U32, progress: Result<&2, &2, Core.Error, Progress>) -> Result<&2, &2, Core.Error, String>:
  match fuel progress:
    case _ Fail{error}: Fail{error}
    case _ Done{Complete{output}}: Done{output}
    case SNil{} _: Fail{Core.Overflow{}}
    case SCon{_, rest} Done{Active{state}}: loop(rest, text, basics, total, pass(text, basics, total, state))

def initial(done: Bool, count: U32, reversed: String) -> Progress:
  match done:
    case True{}: Complete{String.reverse(reversed)}
    case False{}: Active{State{128, 0, 72, count, reversed}}

def prepared(+text: String, result: Result<&2, &2, Core.Error, Basics>) -> Result<&2, &2, Core.Error, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Basics{+count, +total, +reversed}}:
      loop(text, text, count, total, Done{initial(U32.is_eq(count, total), count, Bool.pick(String, U32.is_eq(count, 0), reversed, SCon{'-', reversed}))})

def encode(+text: String) -> Result<&2, &2, Core.Error, String>:
  prepared(text, basics(text, Done{Basics{0, 0, ""}}))
