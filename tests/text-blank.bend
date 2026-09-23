import Base
import ../packages/runtime/src/text.bend as Text

def spaces(count: Nat,result: String) -> String:
  match count:
    case Zero{}: result
    case Succ{rest}: spaces(rest,SCon{' ',result})
def main() -> IO(Unit):
  IO.print(Bool.pick(String,Text.blank(spaces(100000n,"")) && Bool.not(Text.blank(SCon{'x',spaces(100000n,"")})) && Bool.not(Text.blank(spaces(100000n,"x"))),"long blank and nonblank checks passed","FAIL"))
