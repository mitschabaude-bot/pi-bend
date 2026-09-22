import Base
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/test/utf8-runner.bend as Scalar

def repeated(count: Nat, +byte: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: reversed
    case Succ{rest}: repeated(rest, byte, byte <> reversed)

def many(count: Nat, +code: U32, reversed: List<&2, Edns.Option>) -> List<&2, Edns.Option>:
  match count:
    case Zero{}: reversed
    case Succ{rest}: many(rest, code, Edns.Option{code, Nil{}} <> reversed)

def options(empty: Bool, duplicate: Bool, repeatedOptions: Bool, count: Nat, byte: U32, +code: U32) -> List<&2, Edns.Option>:
  match empty duplicate repeatedOptions:
    case True{} _ _: Nil{}
    case False{} _ True{}: many(count, code, Nil{})
    case False{} True{} False{}: Edns.Option{0, Nil{}} <> Edns.Option{code, repeated(count, byte, Nil{})} <> Edns.Option{65535, 0 <> 255 <> Nil{}} <> Edns.Option{code, Nil{}} <> Nil{}
    case False{} False{} False{}: Edns.Option{code, repeated(count, byte, Nil{})} <> Nil{}

def hexDigit(+value: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32))}

def hex(bytes: List<&2, U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: hex(rest, SCon{hexDigit((byte % 16 : U32)), SCon{hexDigit((byte / 16 : U32)), reversed}})

def parsed(value: Result<&2, &2, Message.Error, Message.Message>) -> String:
  match value:
    case Fail{_}: "parse-failed"
    case Done{Message.Message{_, Message.Header{_, _, questions, _, _, additional}, _, _, _, _}}: "counts:" ++ U32.show(questions) ++ ":" ++ U32.show(additional)

def report(value: Result<&2, &2, Edns.EdnsError, List<&2, U32>>) -> IO(Unit):
  match value:
    case Fail{Edns.EdnsInvalidField{}}: IO.print("field")
    case Fail{Edns.InvalidByte{value}}: IO.print("byte:" ++ U32.show(value))
    case Fail{Edns.TooLong{}}: IO.print("long")
    case Fail{Edns.EdnsMessage{_}}: IO.print("message")
    case Done{+bytes}:
      do IO<Unit>:
        IO.print(hex(bytes, ""))
        IO.print(parsed(Message.parse(bytes)))

def args(values: List<String>) -> IO(Unit):
  match values:
    case id <> flags <> payload <> dnssec <> kind <> class <> +mode <> count <> byte <> code <> Nil{}:
      report(Edns.queryEdns(Scalar.decimal(id, 0), Scalar.decimal(flags, 0), Message.Question{Name.Name{(97 <> Nil{}) <> Nil{}}, Scalar.decimal(kind, 0), Scalar.decimal(class, 0)}, Edns.Query{Scalar.decimal(payload, 0), String.eq(dnssec, "1"), options(String.eq(mode, "empty"), String.eq(mode, "duplicate"), String.eq(mode, "many"), U32.to_nat(Scalar.decimal(count, 0)), Scalar.decimal(byte, 0), Scalar.decimal(code, 0))}))
    case _: IO.die(Unit, 1, "expected id flags payload dnssec kind class mode count byte code")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
