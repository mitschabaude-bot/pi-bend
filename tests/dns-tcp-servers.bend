import Base
import ../packages/runtime/src/dns-transport.bend as Servers
import ../packages/runtime/src/dns-transport.bend as Query
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-transport.bend as Session
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/string.bend as Split
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

def outcome(value: Result<&2, &2, Servers.TcpServersError<String>, Query.Reply>) -> String:
  match value:
    case Done{Query.TcpQueryAnswer{Message.Message{_, Message.Header{_, flags, _, _, _, _}, _, _, _, _}}}: "reply:" ++ U32.show((flags % 16 : U32))
    case Done{Query.TcpQueryTruncated{_}}: "truncated"
    case Fail{Servers.Failed{Query.Completed{Fail{Query.Submission{Session.Extension{Edns.EdnsInvalidField{}}}}, Done{_}}}}: "extension-field"
    case Fail{Servers.NoServers{}}: "no-servers"
    case Fail{Servers.Failed{Query.Completed{result, Done{_}}}}: QueryTest.outcome(result)
    case _: "cleanup"

def extension(none: Bool, payload: String) -> Maybe<&2, Edns.Query>:
  match none:
    case True{}: None{}
    case False{}: Some{Edns.Query{Scalar.decimal(payload, 0), True{}, Edns.Option{65001, 0 <> 255 <> Nil{}} <> Edns.Option{65001, Nil{}} <> Nil{}}}

def run(mode: String, opt: Maybe<&2, Edns.Query>, servers: List<&2, Servers.Server>, kind: U32, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        result : Result<&2, &2, Servers.TcpServersError<String>, Query.Reply> <- Servers.exchangeRequestTcpServers(String, servers, signal, Request.Request{42, 256, Message.Question{Name.Name{(97 <> Nil{}) <> Nil{}}, kind, 1}, opt}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        IO.print(outcome(result))
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        IO.print(QueryTest.retained(reason))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> +payload <> family <> portText <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent))
        run(mode, extension(String.eq(payload, "none"), payload), serverInput(family, portText), Scalar.decimal(kind, 0), Deadline.borrow(String, scope))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected mode payload family ports kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
