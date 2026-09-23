import Base
import ../packages/coding-agent/src/core/tools/output-accumulator.bend as Output
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire
import ./tool-truncate.bend as Render

def nibble(+char: Char) -> U32:
  +code = Char.to_u32(char)
  Bool.pick(U32,U32.is_le(code,57),(code - 48 : U32),(code - 87 : U32))
def bytes(text: String, reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SCon{a,SCon{b,rest}}: bytes(rest,(nibble(a) * 16 + nibble(b) : U32) <> reversed)
    case _: List.reverse(&2,U32,reversed)

def error(value: Output.Error) -> String:
  match value:
    case Output.Finished{}: "finished"
    case Output.Closed{}: "closed"
    case Output.InvalidByte{value}: "invalid:" ++ U32.show(value)
    case Output.System{op,code,_}: op ++ ":" ++ U32.show(code)
    case Output.WriteAndClose{wc,_,cc,_}: "write-close:" ++ U32.show(wc) ++ ":" ++ U32.show(cc)

def status(value: Result<&2,&2,Output.Error,Unit>) -> String:
  match value:
    case Done{Unit{}}: "ok"
    case Fail{cause}: error(cause)

def snapshotText(last: Nat, value: Output.OutputSnapshot) -> String:
  match value:
    case Output.OutputSnapshot{_,truncation,path}: Render.report(truncation) ++ "|" ++ Nat.show(last) ++ "|" ++ Maybe.default(&2,String,path,"")

def reportSnapshot(result: String, value: Output.OutputAccumulator & Nat) -> IO(Output.OutputAccumulator):
  match value:
    case Tuple{Output.OutputAccumulator{+state,storage},last}:
      do IO<Output.OutputAccumulator>:
        IO.print(result ++ "|" ++ snapshotText(last,Output.peek(state)))
        return Output.OutputAccumulator{state,storage}

def report(value: Output.Outcome<Unit>) -> IO(Output.OutputAccumulator):
  match value:
    case Output.Outcome{accumulator,result}: reportSnapshot(status(result),Output.getLastLineBytes(accumulator))

def snapshotUnit(value: Output.Outcome<Output.OutputSnapshot>) -> Output.Outcome<Unit>:
  match value:
    case Output.Outcome{accumulator,Done{_}}: Output.Outcome{accumulator,Done{Unit{}}}
    case Output.Outcome{accumulator,Fail{cause}}: Output.Outcome{accumulator,Fail{cause}}

def repeated(n: Nat, rest: List<&2,U32>) -> List<&2,U32>:
  match n:
    case 0n: rest
    case 1n+n: repeated(n,120 <> rest)

def action(command: String, accumulator: Output.OutputAccumulator) -> IO(Output.Outcome<Unit>):
  match command:
    case "L": Output.append(repeated(200000n,10 <> 108 <> 97 <> 115 <> 116 <> 10 <> Nil{}),accumulator)
    case "f": Output.finish(accumulator)
    case "c": Output.closeTempFile(accumulator)
    case "s":
      do IO<Output.Outcome<Unit>>:
        result : Output.Outcome<Output.OutputSnapshot> <- Output.snapshot(True{},accumulator)
        return snapshotUnit(result)
    case "x": Output.append(256 <> Nil{},accumulator)
    case value: Output.append(bytes(value,Nil{}),accumulator)

def actions(commands: List<&2,String>, accumulator: Output.OutputAccumulator) -> IO(Unit):
  match commands:
    case Nil{}:
      do IO<Unit>:
        result : Output.Outcome<Unit> <- Output.closeTempFile(accumulator)
        last : Output.OutputAccumulator <- report(result)
        return Unit{}
    case command <> rest:
      do IO<Unit>:
        result : Output.Outcome<Unit> <- action(command,accumulator)
        next : Output.OutputAccumulator <- report(result)
        actions(rest,next)

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case lines <> maximum <> commands <> Nil{}:
      do IO<Unit>:
        actions(Strings.split(commands,';'),Output.create(Output.OutputAccumulatorOptions{Render.option(lines),Render.option(maximum),Some{"pi-bend-output-test"}}))
        IO.print("end")
    case _: IO.print("invalid-case")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        run(Strings.split(value,':'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
