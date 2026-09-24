import Base
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/session-persistence.bend as P
import ../packages/runtime/src/schema-value.bend as V

def State() -> Data: S.SessionManager<Unit,Unit,V.Value>
def unitValue(_: Unit) -> V.Value: V.Null{}
def same(value: V.Value) -> V.Value: value
def checked(result: Result<&2,&2,S.Error,State()>) -> IO(State()):
  match result:
    case Done{state}: IO.pure(State(),state)
    case Fail{_}: IO.die(State(),1,"could not construct branch")
def printed(result: P.Outcome(String)) -> IO(Unit):
  match result:
    case Done{text}: IO.print(text)
    case Fail{error}: IO.die(Unit,1,P.message(error))
def main() -> IO(Unit):
  do IO<Unit>:
    initial : State() <- checked(S.inMemory(Unit,Unit,V.Value,S.SessionHeader{Some{3n},"export-session","2026-01-01T00:00:00.000Z","/tmp/export",None{}}))
    first : State() <- checked(S.appendCustomEntry(Unit,Unit,V.Value,initial,S.EntryStamp{"a","2026-01-01T00:00:01.000Z"},"note",None{}))
    discarded : State() <- checked(S.appendCustomEntry(Unit,Unit,V.Value,first,S.EntryStamp{"b","2026-01-01T00:00:02.000Z"},"note",None{}))
    branch : State() <- checked(S.branch(Unit,Unit,V.Value,discarded,"a"))
    current : State() <- checked(S.appendCustomEntry(Unit,Unit,V.Value,branch,S.EntryStamp{"c","2026-01-01T00:00:03.000Z"},"note",None{}))
    printed(P.branchContent(~Unit,~Unit,~V.Value,~unitValue,~unitValue,~same,current,"2026-02-01T00:00:00.000Z"))
