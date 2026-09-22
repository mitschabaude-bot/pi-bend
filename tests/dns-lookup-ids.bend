import Base
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-address-lookup.bend as LookupTest
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-connection.bend as Test

type Source is Data:
  Source{mode: String, count: Ref.Ref<U32>, parent: Abort.AbortController<String>}

def numbered(index: U32) -> Result<&2, &2, Id.IdError, U32>:
  match index:
    case 0: Done{0}
    case 1: Done{65535}
    case _: Done{4660}

def drawResult(fail: Bool, code: U32, index: U32) -> Result<&2, &2, Id.IdError, U32>:
  match fail:
    case True{}: Fail{Id.SourceFailure{code, "test source unavailable"}}
    case False{}: numbered(index)

def draw(environment: Source) -> IO(Result<&2, &2, Id.IdError, U32>):
  match environment:
    case Source{+mode, count, parent}:
      do IO<Result<&2, &2, Id.IdError, U32>>:
        +index : U32 <- Ref.modify(U32, U32, count, +n => (U32.add(n, 1), n))
        QueryTest.prepare(String.eq(mode, "abort-source"), False{}, parent)
        return drawResult(String.eq(mode, "error-first") || (String.eq(mode, "error-second") && U32.is_eq(index, 1)), Bool.pick(U32, String.eq(mode, "error-first"), 11, 38), index)

def sourceReport(value: Lookup.Report<String>) -> IO(Unit):
  match value:
    case Lookup.Report{Fail{Lookup.Identifier{Id.SourceFailure{code, message}}}, reason}:
      do IO<Unit>:
        IO.print("entropy:" ++ U32.show(code) ++ ":" ++ message)
        IO.print(QueryTest.retained(reason))
    case other: LookupTest.report(other)

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        result : Lookup.Report<String> <- Lookup.lookupWithAddressLookup(~Source, ~draw, String, Source{mode, count, parent}, Test.endpoint(family), Scalar.decimal(port, 0), Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent), Scalar.decimal(kind, 0), Name.Name{(97 <> Nil{}) <> Nil{}}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        sourceReport(result)
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
        IO.print("PASS DNS lookup IDs")
    case _: IO.die(Unit, 1, "expected mode family port kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
