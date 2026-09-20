import Base
import ../src/dns-pending.bend as Pending
import ../src/dns-response.bend as Response
import ../src/dns-message.bend as Message
import ../src/dns-name.bend as Name
import ../src/string-split.bend as Split
import ../src/url-ipv4.bend as IPv4
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def octets(text: String) -> List<&2, U32>:
  numbers(Split.split(text, ','), Nil{})

def endpoint(mode: U32, destination: Bool) -> Response.Endpoint:
  Response.Endpoint{Response.V4{IPv4.Address{2130706433}}, Bool.pick(U32, destination, 40000, Bool.pick(U32, U32.is_eq(mode, 0), 53, 54))}

def rejectionLabel(value: Response.Rejection) -> String:
  match value:
    case Response.EndpointMismatch{}: "endpoint"
    case Response.IdMismatch{}: "id"
    case Response.NotResponse{}: "query"
    case Response.OpcodeMismatch{}: "opcode"
    case Response.QuestionCountMismatch{}: "count"
    case Response.QuestionMismatch{}: "question"
    case Response.Malformed{_}: "malformed"

type State is Data:
  State{pending: Pending.Pending<U32>, saved: Pending.Pending<U32>}

type Output is Data:
  Output{state: State, text: String}

def registration(result: Result<&2, &2, Pending.RegistrationError, Pending.Ticket>) -> String:
  match result:
    case Done{_}: "added"
    case Fail{Pending.DuplicateId{}}: "duplicate"
    case Fail{Pending.InvalidId{}}: "invalid"
    case Fail{Pending.Exhausted{}}: "exhausted"

def registered(saved: Pending.Pending<U32>, result: Pending.Registered<U32>) -> Output:
  match result:
    case Pending.Registered{pending, status}: Output{State{pending, saved}, registration(status)}

def token(entry: Maybe<&2, Pending.Entry<U32>>) -> String:
  match entry:
    case None{}: "none"
    case Some{Pending.Entry{_, value, _}}: "removed:" ++ U32.show(value)

def removed(saved: Pending.Pending<U32>, result: Pending.Removed<U32>) -> Output:
  match result:
    case Pending.Removed{pending, entry}: Output{State{pending, saved}, token(entry)}

def delivery(value: Pending.Delivery<U32>) -> String:
  match value:
    case Pending.Ignored{Pending.MissingId{}}: "missing"
    case Pending.Ignored{Pending.UnknownId{id}}: "unknown:" ++ U32.show(id)
    case Pending.Ignored{Pending.Mismatch{reason}}: "ignore:" ++ rejectionLabel(reason)
    case Pending.Answer{token, _}: "answer:" ++ U32.show(token)
    case Pending.Truncated{token, _}: "truncated:" ++ U32.show(token)

def received(saved: Pending.Pending<U32>, result: Pending.Received<U32>) -> Output:
  match result:
    case Pending.Received{pending, value}: Output{State{pending, saved}, delivery(value)}

def command(parts: List<&2, String>, state: State) -> Output:
  match parts state:
    case "add" <> id <> value <> kind <> Nil{} State{pending, saved}: registered(saved, Pending.register(U32, pending, Response.Transaction{endpoint(0, True{}), endpoint(0, False{}), Scalar.decimal(id, 0), 0, Message.Question{Name.Name{Nil{}}, Scalar.decimal(kind, 0), 1}}, Scalar.decimal(value, 0)))
    case "remove" <> id <> Nil{} State{pending, saved}: removed(saved, Pending.remove(U32, pending, Scalar.decimal(id, 0)))
    case "cancel" <> id <> serial <> Nil{} State{pending, saved}: removed(saved, Pending.cancel(U32, pending, Pending.Ticket{Scalar.decimal(id, 0), Scalar.decimal(serial, 0)}))
    case "seed" <> serial <> Nil{} State{Pending.Pending{entries, _}, saved}: Output{State{Pending.Pending{entries, Some{Scalar.decimal(serial, 0)}}, saved}, "seeded"}
    case "recv" <> mode <> wire <> Nil{} State{pending, saved}: received(saved, Pending.receive(U32, pending, endpoint(Scalar.decimal(mode, 0), False{}), endpoint(0, True{}), octets(wire)))
    case "save" <> Nil{} State{+pending, _}: Output{State{pending, pending}, "saved"}
    case "restore" <> Nil{} State{_, +saved}: Output{State{saved, saved}, "restored"}
    case _ state: Output{state, "invalid test command"}

def printed(output: Output) -> IO(State):
  match output:
    case Output{state, text}:
      do IO<State>:
        IO.print(text)
        return state

def commands(args: List<String>, state: State) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        state : State <- printed(command(Split.split(arg, ':'), state))
        commands(rest, state)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    commands(args, State{Pending.new(U32), Pending.new(U32)})
