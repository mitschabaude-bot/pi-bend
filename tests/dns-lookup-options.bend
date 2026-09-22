import Base
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-transport.bend as Selector
import ../packages/runtime/src/dns-transport.bend as Servers
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-connection.bend as Test

def settings() -> Request.QueryOptions:
  Request.QueryOptions{288, Some{Edns.Query{1232, True{}, Edns.Option{65001, 0 <> 255 <> Nil{}} <> Edns.Option{65001, Nil{}} <> Nil{}}}}

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        result : Lookup.Report<String> <- Lookup.lookupSourceOptionsWith(~IDs.Source, ~IDs.draw, String, IDs.Source{mode, count, parent}, Selector.Fixed{Servers.Server{Test.endpoint(family), Scalar.decimal(port, 0)} <> Nil{}}, Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent), settings(), Scalar.decimal(kind, 0), Name.Name{(97 <> Nil{}) <> Nil{}}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        IDs.sourceReport(result)
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
        IO.print("PASS DNS lookup IDs")
    case _: IO.die(Unit, 1, "expected mode family port kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
