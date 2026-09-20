import Base
import ../packages/runtime/src/dns-tcp-servers.bend as Servers
import ../packages/runtime/src/dns-tcp-query.bend as Query
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-connection.bend as Test

def ports(+family: String, values: List<&2, String>, reversed: List<&2, Servers.Server>) -> List<&2, Servers.Server>:
  match values:
    case Nil{}: List.reverse(&2, Servers.Server, reversed)
    case value <> rest: ports(family, rest, Servers.Server{Test.endpoint(family), Scalar.decimal(value, 0)} <> reversed)

def serverInput(family: String, values: String) -> List<&2, Servers.Server>:
  match values:
    case SNil{}: Nil{}
    case other: ports(family, Split.split(other, ','), Nil{})

def outcome(value: Result<&2, &2, Servers.Error<String>, Query.Reply>) -> String:
  match value:
    case Done{Query.Answer{Message.Message{_, Message.Header{_, flags, _, _, _, _}, _, _, _, _}}}: "reply:" ++ U32.show((flags % 16 : U32))
    case Done{Query.Truncated{_}}: "truncated"
    case Fail{Servers.NoServers{}}: "no-servers"
    case Fail{Servers.Failed{Query.Completed{result, Done{_}}}}: QueryTest.outcome(result)
    case _: "cleanup"

def run(mode: String, servers: List<&2, Servers.Server>, kind: U32, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        result : Result<&2, &2, Servers.Error<String>, Query.Reply> <- Servers.exchange(String, servers, signal, 42, 256, Message.Question{Name.Name{(97 <> Nil{}) <> Nil{}}, kind, 1}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        IO.print(outcome(result))
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        IO.print(QueryTest.retained(reason))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> portText <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent))
        run(mode, serverInput(family, portText), Scalar.decimal(kind, 0), Deadline.borrow(String, scope))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected mode family ports kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
