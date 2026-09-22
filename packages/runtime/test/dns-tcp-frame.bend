import Base
import ../src/dns-message.bend as Frame
import ../src/string.bend as Split
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def octets(text: String) -> List<&2, U32>:
  numbers(Split.split(text, ','), Nil{})

def digest(input: List<&2, U32>, count: U32, hash: U32) -> String:
  match input:
    case Nil{}: U32.show(count) ++ "," ++ U32.show(hash)
    case value <> rest: digest(rest, (count + 1 : U32), U32.xor((hash * 16777619 : U32), value))

def error(value: Frame.TcpFrameError) -> String:
  match value:
    case Frame.TcpFrameInvalidByte{value}: "byte:" ++ U32.show(value)
    case Frame.TcpFrameTooLong{}: "long"
    case Frame.IncompleteFrame{}: "incomplete"

def ending(value: Result<&2, &2, Frame.TcpFrameError, Unit>) -> String:
  match value:
    case Done{_}: "done"
    case Fail{why}: error(why)

type State is Data:
  Active{reader: Frame.Reader, reversed: List<&2, String>}
  Failed{error: String, reversed: List<&2, String>}

def fuel(input: List<&2, U32>, count: Nat) -> Nat:
  match input:
    case Nil{}: Succ{count}
    case _ <> rest: fuel(rest, Succ{count})

def drain(count: Nat, reversed: List<&2, String>, value: Frame.ReadResult) -> State:
  match count value:
    case _ Frame.More{reader}: Active{reader, reversed}
    case _ Frame.TcpFrameFailed{why}: Failed{error(why), reversed}
    case Succ{rest} Frame.Frame{bytes, unread}: drain(rest, digest(bytes, 0, 2166136261) <> reversed, Frame.read(Frame.newTcpFrame(), unread))
    case Zero{} _: Failed{"test fuel", reversed}

def chunk(+input: List<&2, U32>, state: State) -> State:
  match state:
    case Active{reader, reversed}: drain(fuel(input, Zero{}), reversed, Frame.read(reader, input))
    case failed: failed

def chunks(input: List<&2, String>, state: State) -> State:
  match input:
    case Nil{}: state
    case first <> rest: chunks(rest, chunk(octets(first), state))

def report(state: State) -> String:
  match state:
    case Active{reader, reversed}: String.join(List.reverse(&2, String, reversed), ";") ++ "|" ++ ending(Frame.finish(reader))
    case Failed{why, reversed}: String.join(List.reverse(&2, String, reversed), ";") ++ "|" ++ why

def encoded(value: Result<&2, &2, Frame.TcpFrameError, List<&2, U32>>) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{bytes}: "ok:" ++ digest(bytes, 0, 2166136261)

def zeros(count: Nat, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: reversed
    case Succ{rest}: zeros(rest, 0 <> reversed)

def singles(input: List<&2, U32>, state: State) -> State:
  match input:
    case Nil{}: state
    case byte <> rest: singles(rest, chunk(byte <> Nil{}, state))

def framed(value: Result<&2, &2, Frame.TcpFrameError, List<&2, U32>>) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{bytes}: report(singles(bytes, Active{Frame.newTcpFrame(), Nil{}}))

def run(input: String) -> String:
  match input:
    case SCon{'e', text}: encoded(Frame.encodeTcpFrame(octets(text)))
    case SCon{'r', text}: report(chunks(Split.split(text, '/'), Active{Frame.newTcpFrame(), Nil{}}))
    case SCon{'l', text}: framed(Frame.encodeTcpFrame(zeros(U32.to_nat(Scalar.decimal(text, 0)), Nil{})))
    case _: "bad mode"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        IO.print(run(arg))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
