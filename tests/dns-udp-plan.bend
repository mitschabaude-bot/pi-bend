import Base
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/resolver-config.bend as Timeout
import ../packages/runtime/src/resolver-config.bend as Schedule
import ../packages/runtime/src/dns-transport.bend as Rotation
import ../packages/runtime/test/utf8-runner.bend as Scalar

def servers(count: Nat, +index: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: List.reverse(&2, U32, reversed)
    case Succ{rest}: servers(rest, (index + 1 : U32), (index % 2 : U32) <> reversed)

def position(value: Timeout.Position) -> String:
  match value:
    case Timeout.First{}: "first"
    case Timeout.SecondOfTwo{}: "second2"
    case Timeout.SecondOfThree{}: "second3"
    case Timeout.ThirdOfThree{}: "third3"

def show(value: Plan.Attempt<U32>) -> String:
  match value:
    case Plan.Attempt{server, at, duration}: U32.show(server) ++ "@" ++ position(at) ++ "=" ++ U32.show(U32.from_nat(Timeout.seconds(duration))) ++ ";"

def trace(fuel: Nat, step: Schedule.Step<Plan.Attempt<U32>>, reversed: String) -> String:
  match fuel step:
    case _ Schedule.Exhausted{}: String.reverse(reversed)
    case Zero{} Schedule.Try{_, _}: "fuel-exhausted"
    case Succ{rest} Schedule.Try{entry, next}: trace(rest, Schedule.next(Plan.Attempt<U32>, next), String.reverse(show(entry)) ++ reversed)

def chosen(+attempts: U32, choice: Rotation.Chosen<Plan.Attempt<U32>>) -> String:
  match choice:
    case Rotation.Chosen{entries, _}: trace(U32.to_nat((attempts * 3 + 1 : U32)), Schedule.next(Plan.Attempt<U32>, Schedule.start(Plan.Attempt<U32>, U32.to_nat(attempts), entries)), "")

def prepared(offset: Nat, attempts: U32, result: Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<U32>>>) -> String:
  match result:
    case Fail{Plan.NoServers{}}: "no-servers"
    case Fail{Plan.TooManyServers{}}: "too-many"
    case Fail{Plan.InvalidTimeout{seconds}}: "invalid:" ++ U32.show(seconds)
    case Done{entries}: chosen(attempts, Rotation.choose(Plan.Attempt<U32>, True{}, Rotation.startAt(Plan.Attempt<U32>, offset, entries)))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case timeout <> count <> offset <> attempts <> rest:
      do IO<Unit>:
        IO.print(prepared(U32.to_nat(Scalar.decimal(offset, 0)), Scalar.decimal(attempts, 0), Plan.prepare(U32, Scalar.decimal(timeout, 0), servers(U32.to_nat(Scalar.decimal(count, 0)), 0, Nil{}))))
        run(rest)
    case _: IO.die(Unit, 1, "expected timeout/count/offset/attempts groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
