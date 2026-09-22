import Base
import ../packages/runtime/src/text-decoder.bend as Text

def value(point: Maybe<&2,Char>) -> Nat:
  match point:
    case None{}: 0n
    case Some{char}: U32.to_nat(Char.to_u32(char))
def run(remaining: Nat,result: Result<&2,&2,Text.Error,Text.Step>,total: Nat) -> String:
  match remaining result:
    case _ Fail{_}: "error"
    case Zero{} Done{Text.Step{Text.Decoder{_,offset},point}}: Nat.show(offset) ++ ":" ++ Nat.show(total + value(point))
    case Succ{rest} Done{Text.Step{decoder,point}}: run(rest,Text.step(decoder,97),total + value(point))
def main() -> IO(Unit): IO.print(run(1048576n,Done{Text.Step{Text.create(),None{}}},0n))
