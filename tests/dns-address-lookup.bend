import Base
import ../packages/runtime/src/dns-address-lookup.bend as Lookup
import ../packages/runtime/src/dns-address-answer.bend as Answer
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/runtime/test/dns-address-answer.bend as AnswerTest
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-connection.bend as Test

def outcome(value: Result<&2, &2, Lookup.Error<String>, Answer.Selection>) -> String:
  match value:
    case Done{selection}: AnswerTest.show(Done{selection})
    case Fail{Lookup.InvalidReadSize{}}: "zero"
    case Fail{Lookup.NoServers{}}: "no-servers"
    case Fail{Lookup.UnsupportedType{}}: "type"
    case Fail{Lookup.Exchange{error}}: QueryTest.outcome(Fail{error})
    case Fail{Lookup.Selection{error}}: AnswerTest.show(Fail{error})
    case Fail{Lookup.Truncated{_}}: "truncated"
    case _: "unexpected"

def report(value: Lookup.Report<String>) -> IO(Unit):
  match value:
    case Lookup.Report{result, reason}:
      do IO<Unit>:
        IO.print(outcome(result))
        IO.print(QueryTest.retained(reason))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        result : Lookup.Report<String> <- Lookup.lookup(String, Test.endpoint(family), Scalar.decimal(port, 0), Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent), 42, Scalar.decimal(kind, 0), Name.Name{(97 <> Nil{}) <> Nil{}}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        report(result)
        Abort.dispose(String, parent)
        IO.print("PASS DNS address lookup")
    case _: IO.die(Unit, 1, "expected mode family port kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
