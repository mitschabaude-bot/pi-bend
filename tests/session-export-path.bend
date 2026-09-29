import Base
import ../packages/coding-agent/src/core/session-manager.bend as Session
import ../packages/coding-agent/src/core/session-export.bend as Export
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/filesystem.bend as FS

def plain(_: Unit) -> Value.Value: Value.Null{}
def same(value: Value.Value) -> Value.Value: value
def created(result: Result<&2,&2,Session.Error,Session.SessionManager<Unit,Unit,Value.Value>>) -> IO(Session.SessionManager<Unit,Unit,Value.Value>):
  match result:
    case Done{state}: IO.pure(Session.SessionManager<Unit,Unit,Value.Value>,state)
    case Fail{_}: IO.die(Session.SessionManager<Unit,Unit,Value.Value>,1,"could not create session")
def report(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Done{path}: IO.print(path)
    case Fail{message}: IO.die(Unit,1,message)
def directory(result: Result<&2,&2,FS.Error,String>) -> IO(String):
  match result:
    case Done{path}: IO.pure(String,path)
    case Fail{error}: IO.die(String,1,FS.errorMessage(error))
def main() -> IO(Unit):
  do IO<Unit>:
    current : Result<&2,&2,FS.Error,String> <- FS.cwd()
    +cwd : String <- directory(current)
    +state : Session.SessionManager<Unit,Unit,Value.Value> <- created(Session.inMemory(Unit,Unit,Value.Value,Session.SessionHeader{Some{3n},"export-id","2026-01-01T00:00:00.000Z","/tmp/export",None{}}))
    default : Result<&2,&2,String,String> <- Export.exportSessionToJsonl(~Unit,~Unit,~Value.Value,~plain,~plain,~same,state,cwd,None{},"2026-02-01T12:34:56.789Z",_ => _ => Nil{})
    report(default)
    explicit : Result<&2,&2,String,String> <- Export.exportSessionToJsonl(~Unit,~Unit,~Value.Value,~plain,~plain,~same,state,cwd,Some{"nested/explicit.jsonl"},"2026-02-01T12:34:56.789Z",_ => _ => Nil{})
    report(explicit)
