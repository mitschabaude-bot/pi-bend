import Base
import ../src/idna.bend as Rule
import ../src/unicode.bend as Joining

def step(code: U32, state: Rule.ContextjState) -> Rule.ContextjState:
  match code:
    case 97: Rule.pushContextj(state, 97, Joining.NonJoining{}, 0)
    case 98: Rule.pushContextj(state, 97, Joining.LeftJoining{}, 0)
    case 99: Rule.pushContextj(state, 97, Joining.RightJoining{}, 0)
    case 100: Rule.pushContextj(state, 97, Joining.DualJoining{}, 0)
    case 101: Rule.pushContextj(state, 97, Joining.JoinCausing{}, 0)
    case 102: Rule.pushContextj(state, 97, Joining.Transparent{}, 230)
    case 103: Rule.pushContextj(state, 97, Joining.Transparent{}, 9)
    case 104: Rule.pushContextj(state, 97, Joining.NonJoining{}, 9)
    case 105: Rule.pushContextj(state, 8204, Joining.NonJoining{}, 0)
    case _: Rule.pushContextj(state, 8205, Joining.JoinCausing{}, 0)

def run(text: String, state: Rule.ContextjState) -> Bool:
  match text:
    case SNil{}: Rule.finishContextj(state)
    case SCon{Chr{code}, rest}: run(rest, step(code, state))

def show(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(run(head, Rule.startContextj())))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
