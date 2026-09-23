import Base
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/tui-process.bend as Process

def reported(value: Maybe<&2,Terminal.Error>) -> String:
  match value:
    case Some{Terminal.Closed{}}: "closed"
    case _: "missing"
def main() -> IO(Unit):
  do IO<Unit>:
    +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +failure : Deferred.Deferred<Terminal.Error> <- Deferred.new(Terminal.Error)
    Process.matchWrite(Fail{Terminal.Closed{}},stopped,failure)
    ready : Maybe<&2,Unit> <- Deferred.peek(Unit,stopped)
    error : Maybe<&2,Terminal.Error> <- Deferred.peek(Terminal.Error,failure)
    IO.print(Bool.show(Bool.not(Maybe.is_none(&2,Unit,ready))) ++ ":" ++ reported(error))
    Deferred.dispose(Unit,stopped)
    Deferred.dispose(Terminal.Error,failure)
