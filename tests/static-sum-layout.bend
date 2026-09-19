import Base

# A known success contains no live Failure payload. Layout adaptation must not
# interpret its list words as nested Failure tags while generating dead arms.
type InnerError is Data:
  BadText{left: String, right: String}
  BadNumber{code: U32}

type Failure is Data:
  FirstFailure{reason: InnerError}
  SecondFailure{reason: InnerError}

type State is Data:
  State{values: List<&2, String>, keys: List<&2, String>}

def relay(-E: Data, ticks: List<&2, Unit>, value: Result<&2, &2, E, State>) -> IO(Result<&2, &2, E, State>):
  match ticks:
    case Nil{}: IO.pure(Result<&2, &2, E, State>, value)
    case _ <> rest: relay(E, rest, value)

def consume(result: Result<&2, &2, Failure, State>) -> String:
  match result:
    case Fail{FirstFailure{BadText{a, b}}}: "first:" ++ a ++ b
    case Fail{SecondFailure{BadText{a, b}}}: "second:" ++ b ++ a
    case Fail{FirstFailure{BadNumber{number}}}: "first:" ++ U32.show(number)
    case Fail{SecondFailure{BadNumber{number}}}: "second:" ++ U32.show(number)
    case Done{State{values, keys}}: "done:" ++ String.join(values, ",") ++ ";" ++ String.join(keys, ",")

def empty(~E: Data) -> IO(Result<&2, &2, E, State>):
  relay(E, Unit{} <> Nil{}, Done{State{Nil{}, Nil{}}})

def populated(~E: Data) -> IO(Result<&2, &2, E, State>):
  relay(E, Unit{} <> Nil{}, Done{State{"one" <> "two" <> Nil{}, "key" <> Nil{}}})

def failedFirst() -> IO(Result<&2, &2, Failure, State>):
  relay(Failure, Unit{} <> Nil{}, Fail{FirstFailure{BadText{"a", "b"}}})

def failedSecond() -> IO(Result<&2, &2, Failure, State>):
  relay(Failure, Unit{} <> Nil{}, Fail{SecondFailure{BadNumber{42}}})

def assertion(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "wrong converted sum payload")

def check(+value: Result<&2, &2, Failure, State>, +expected: String) -> IO(Unit):
  do IO<Unit>:
    assertion(String.eq(consume(value), expected))
    roundTrip : Result<&2, &2, Failure, State> <- relay(Failure, Unit{} <> Unit{} <> Nil{}, value)
    assertion(String.eq(consume(roundTrip), expected))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Result<&2, &2, Failure, State> <- empty(~Failure)
    check(a, "done:;")
    b : Result<&2, &2, Failure, State> <- populated(~Failure)
    check(b, "done:one,two;key")
    c : Result<&2, &2, Failure, State> <- failedFirst()
    check(c, "first:ab")
    d : Result<&2, &2, Failure, State> <- failedSecond()
    check(d, "second:42")
    check(Fail{FirstFailure{BadNumber{7}}}, "first:7")
    check(Fail{SecondFailure{BadText{"x", "y"}}}, "second:yx")
    IO.print("PASS static and dynamic sum layout conversion")
