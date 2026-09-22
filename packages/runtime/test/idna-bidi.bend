import Base
import ../src/unicode.bend as Bidi
import ../src/idna.bend as Rule

# Test protocol letters encode the 23 Bidi_Class constructors in declaration order.
def property(code: U32) -> Bidi.Class:
  match code:
    case 97: Bidi.L{}
    case 98: Bidi.R{}
    case 99: Bidi.AL{}
    case 100: Bidi.EN{}
    case 101: Bidi.AN{}
    case 102: Bidi.ES{}
    case 103: Bidi.CS{}
    case 104: Bidi.ET{}
    case 105: Bidi.ON{}
    case 106: Bidi.BN{}
    case 107: Bidi.NSM{}
    case 108: Bidi.B{}
    case 109: Bidi.S{}
    case 110: Bidi.WS{}
    case 111: Bidi.LRE{}
    case 112: Bidi.LRO{}
    case 113: Bidi.RLE{}
    case 114: Bidi.RLO{}
    case 115: Bidi.PDF{}
    case 116: Bidi.LRI{}
    case 117: Bidi.RLI{}
    case 118: Bidi.FSI{}
    case _: Bidi.PDI{}

def run(text: String, state: Rule.State) -> Rule.Analysis:
  match text:
    case SNil{}: Rule.finish(state)
    case SCon{Chr{code}, rest}: run(rest, Rule.push(state, property(code)))

def bit(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def show(result: Rule.Analysis) -> String:
  match result:
    case Rule.Analysis{rtl, valid}: bit(rtl) ++ bit(valid)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(run(head, Rule.start())))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
