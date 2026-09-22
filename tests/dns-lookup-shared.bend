import Base
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-connection.bend as Test

def pause(expire: Bool) -> IO(Unit):
  match expire:
    case True{}: IO.sleep(1200)
    case False{}: IO.pure(Unit, Unit{})

def run(+mode: String, +source: IDs.Source, +address: Connect.Address, +port: U32, +kind: U32, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair:
    case (scope, +signal):
      do IO<Unit>:
        first : Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection> <- Lookup.exchangeWith(~IDs.Source, ~IDs.draw, String, source, address, port, signal, kind, Name.Name{(97 <> Nil{}) <> Nil{}}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        IDs.sourceReport(Lookup.Report{first, None{}})
        pause(String.eq(mode, "expiry-before"))
        second : Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection> <- Lookup.exchangeWith(~IDs.Source, ~IDs.draw, String, source, address, port, signal, kind, Name.Name{(98 <> Nil{}) <> Nil{}}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        IDs.sourceReport(Lookup.Report{second, None{}})
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        IO.print(QueryTest.retained(reason))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        scope : Deadline.Scope<String> <- Deadline.create(String, 1000, Abort.signal(String, parent))
        run(mode, IDs.Source{mode, count, parent}, Test.endpoint(family), Scalar.decimal(port, 0), Scalar.decimal(kind, 0), Deadline.borrow(String, scope))
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected mode family port kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
