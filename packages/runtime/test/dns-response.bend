import Base
import ../src/dns-message.bend as Response
import ../src/dns-message.bend as Message
import ../src/url-ipv4.bend as IPv4
import ../src/url-ipv6.bend as IPv6
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def octets(text: String) -> List<&2, U32>:
  numbers(Split.split(text, ','), Nil{})

def reason(value: Response.Rejection) -> String:
  match value:
    case Response.EndpointMismatch{}: "endpoint"
    case Response.IdMismatch{}: "id"
    case Response.NotResponse{}: "query"
    case Response.OpcodeMismatch{}: "opcode"
    case Response.QuestionCountMismatch{}: "count"
    case Response.QuestionMismatch{}: "question"
    case Response.Malformed{_}: "malformed"

def flags(prefix: String, value: Message.Header) -> String:
  match value:
    case Message.Header{_, flags, _, _, _, _}: prefix ++ U32.show(flags)

def show(value: Response.Decision) -> String:
  match value:
    case Response.Ignore{why}: "ignore:" ++ reason(why)
    case Response.ResponseTruncated{head}: flags("truncated:", head)
    case Response.Matched{Message.Message{_, head, _, _, _, _}}: flags("matched:", head)

def ipv6(+mode: U32, destination: Bool) -> Response.Endpoint:
  Response.Endpoint{Response.V6{IPv6.Address{Bool.pick(U32, U32.is_eq(mode, 6), 2, 1), Bool.pick(U32, U32.is_eq(mode, 7), 3, 2), Bool.pick(U32, U32.is_eq(mode, 8), 4, 3), Bool.pick(U32, U32.is_eq(mode, 9), 5, 4)}, Bool.pick(U32, U32.is_eq(mode, 10) || U32.is_eq(mode, 12), 8, 7)}, Bool.pick(U32, destination, 40000, 53)}

def endpoint(v6: Bool, +mode: U32, destination: Bool) -> Response.Endpoint:
  match v6:
    case True{}: ipv6(mode, destination)
    case False{}: Response.Endpoint{Response.V4{IPv4.Address{Bool.pick(U32, U32.is_eq(mode, 2) || U32.is_eq(mode, 4), 2130706434, 2130706433)}}, Bool.pick(U32, U32.is_eq(mode, 3) || U32.is_eq(mode, 5), 54, Bool.pick(U32, destination, 40000, 53))}

def inspect(stream: Bool, transaction: Response.Transaction, source: Response.Endpoint, destination: Response.Endpoint, wire: List<&2, U32>) -> Response.Decision:
  match stream:
    case False{}: Response.inspectResponse(transaction, source, destination, wire)
    case True{}: Response.inspectStream(transaction, source, destination, wire)

def runMode(stream: Bool, +mode: U32, id: U32, opcode: U32, expected: Message.Question, wire: List<&2, U32>) -> String:
  +v6 = U32.is_eq(mode, 1) || U32.is_ge(mode, 6)
  sourceMode = Bool.pick(U32, U32.is_eq(mode, 4) || U32.is_eq(mode, 5) || U32.is_eq(mode, 12), 0, mode)
  destMode = Bool.pick(U32, U32.is_eq(mode, 4) || U32.is_eq(mode, 5) || U32.is_eq(mode, 12), mode, 0)
  show(inspect(stream, Response.Transaction{endpoint(v6, 0, True{}), endpoint(v6, 0, False{}), id, opcode, expected}, endpoint(v6 && Bool.not(U32.is_eq(mode, 11)), sourceMode, False{}), endpoint(v6, destMode, True{}), wire))

def run(+mode: U32, id: U32, opcode: U32, expected: Message.Question, wire: List<&2, U32>) -> String:
  runMode(U32.is_ge(mode, 100), (mode % 100 : U32), id, opcode, expected, wire)

def queried(mode: U32, wire: List<&2, U32>, result: Result<&2, &2, Message.Error, Message.Message>) -> String:
  match result:
    case Done{Message.Message{_, Message.Header{id, flags, _, _, _, _}, expected <> Nil{}, _, _, _}}: run(mode, id, (flags / 2048 % 16 : U32), expected, wire)
    case _: "bad test query"

def argument(parts: List<&2, String>) -> String:
  match parts:
    case mode <> query <> response <> Nil{}: queried(Scalar.decimal(mode, 0), octets(response), Message.parse(octets(query)))
    case _: "bad test input"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        IO.print(argument(Split.split(arg, ':')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
