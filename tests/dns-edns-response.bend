import Base
import ../packages/runtime/src/dns-edns-response.bend as Response
import ../packages/runtime/src/dns-edns.bend as Edns
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/test/utf8-runner.bend as Scalar

def digit(+value: U32) -> U32:
  Bool.pick(U32, U32.is_le(value, 57), (value - 48 : U32), (value - 87 : U32))

def unhex(text: String, reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case SCon{Chr{a}, SCon{Chr{b}, rest}}: unhex(rest, (digit(a) * 16 + digit(b) : U32) <> reversed)
    case _: List.reverse(&2, U32, reversed)

def hexDigit(+value: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32))}

def hex(bytes: List<&2, U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: hex(rest, SCon{hexDigit((byte % 16 : U32)), SCon{hexDigit((byte / 16 : U32)), reversed}})

def optionLines(values: List<&2, Edns.Option>, reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, reversed)
    case Edns.Option{code, data} <> rest: optionLines(rest, (U32.show(code) ++ ":" ++ hex(data, "")) <> reversed)

def lines(values: List<&2, String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case line <> rest:
      do IO<Unit>:
        IO.print(line)
        lines(rest)

def failure(value: Response.Error) -> String:
  match value:
    case Response.Misplaced{}: "misplaced"
    case Response.Duplicate{}: "duplicate"
    case Response.InvalidOwner{}: "owner"
    case Response.InvalidField{}: "field"
    case Response.TruncatedOption{}: "option"

def present(header: Message.Header, +extension: Response.Response) -> IO(Unit):
  match extension:
    case Response.Response{payload, upper, version, flags, values}:
      do IO<Unit>:
        IO.print(U32.show(payload) ++ ":" ++ U32.show(upper) ++ ":" ++ U32.show(version) ++ ":" ++ U32.show(flags) ++ ":" ++ U32.show(Response.responseCode(header, Some{extension})) ++ ":" ++ Bool.pick(String, Response.dnssecOk(extension), "do", "no"))
        lines(optionLines(values, Nil{}))

def report(header: Message.Header, result: Result<&2, &2, Response.Error, Maybe<&2, Response.Response>>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(failure(error))
    case Done{None{}}: IO.print("none:" ++ U32.show(Response.responseCode(header, None{})))
    case Done{Some{extension}}: present(header, extension)

def messageHeader(message: Message.Message) -> Message.Header:
  match message:
    case Message.Message{_, header, _, _, _, _}: header

def parsed(result: Result<&2, &2, Message.Error, Message.Message>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("message")
    case Done{+message}: report(messageHeader(message), Response.inspect(message))

def decoded(result: Result<&2, &2, Response.Error, Response.Response>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(failure(error))
    case Done{extension}: report(Message.Header{0, 0, 0, 0, 0, 0}, Done{Some{extension}})

def direct(result: Result<&2, &2, Name.Error, Name.Packet>, start: U32, length: U32, kind: U32, class: U32) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("packet")
    case Done{packet}: decoded(Response.decode(packet, Message.Record{Name.Name{Nil{}}, kind, class, 0, start, length}))

def args(values: List<String>) -> IO(Unit):
  match values:
    case data <> Nil{}: parsed(Message.parse(unhex(data, Nil{})))
    case data <> start <> length <> kind <> class <> Nil{}: direct(Name.packet(unhex(data, Nil{})), Scalar.decimal(start, 0), Scalar.decimal(length, 0), Scalar.decimal(kind, 0), Scalar.decimal(class, 0))
    case _: IO.die(Unit, 1, "expected packet hex or bytes start length kind class")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
