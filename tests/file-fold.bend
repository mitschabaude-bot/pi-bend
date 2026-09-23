import Base
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-server-rotation.bend as Test

type State is Type:
  State{chunks: U32, remaining: U32, reversed: List<&2, U32>}

def prepend(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case byte <> rest: prepend(rest, byte <> reversed)

def continued(stop: Bool, state: State) -> Fold.Control<State>:
  match stop:
    case True{}: Fold.Stop{state}
    case False{}: Fold.Continue{state}

def consume(state: State, bytes: List<&2, U32>) -> Fold.Control<State>:
  match state:
    case State{chunks, +remaining, reversed}:
      continued(U32.is_eq(remaining, 1), State{(chunks+1:U32), (remaining-1:U32), prepend(bytes, reversed)})

def status(result: Result<&2, &2, Fold.Error, Fold.Completion>) -> String:
  match result:
    case Done{Fold.EndOfFile{}}: "eof"
    case Done{Fold.Stopped{}}: "stopped"
    case Fail{Fold.InvalidReadSize{}}: "size"
    case Fail{Fold.Open{code, _}}: "open:" ++ U32.show(code)
    case Fail{Fold.Read{code, _}}: "read:" ++ U32.show(code)
    case Fail{Fold.Close{code, _}}: "close:" ++ U32.show(code)
    case Fail{Fold.ReadAndClose{code, _, close, _}}: "read-close:" ++ U32.show(code) ++ ":" ++ U32.show(close)

def report(result: Fold.Outcome<State>) -> IO(Unit):
  match result:
    case Fold.Outcome{State{chunks, _, reversed}, outcome}:
      IO.print(status(outcome) ++ ":" ++ U32.show(chunks) ++ ":" ++ Test.csv(List.reverse(&2, U32, reversed), ""))

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case path <> size <> stop <> rest:
      do IO<Unit>:
        outcome : Fold.Outcome<State> <- Fold.read(~State, ~consume, path, Scalar.decimal(size, 0), State{0, Scalar.decimal(stop, 0), 999 <> Nil{}})
        report(outcome)
        args(rest)
    case _: IO.die(Unit, 1, "expected path, chunk size and stop-after count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
