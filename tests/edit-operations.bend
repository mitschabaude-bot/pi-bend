import Base
import ../packages/coding-agent/src/core/tools/edit.bend as E
import ../packages/coding-agent/src/core/tools/edit-diff.bend as D
import ../packages/coding-agent/src/core/tools/write.bend as W
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Q
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as U
import ./file-mutation-queue.bend as T

type Stage is Data:
  Stage{mode: String, controller: A.AbortController<Unit>, calls: R.Ref<String>}

def record(+calls: R.Ref<String>, stage: String) -> IO(Unit):
  do IO<Unit>:
    previous : String <- R.read(String, calls)
    R.write(String, calls, previous ++ stage)

def cancel(+mode: String, +stage: String, controller: A.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    ignored : Bool <- Bool.pick(IO(Bool), String.eq(mode, stage ++ "-abort") || String.eq(mode, stage ++ "-failure"), A.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    return Unit{}

def access(environment: Stage, path: String) -> IO(E.ResultOf(Unit)):
  match environment:
    case Stage{+mode, controller, +calls}:
      do IO<E.ResultOf(Unit)>:
        record(calls, "A")
        cancel(mode, "access", controller)
        return Bool.pick(E.ResultOf(Unit), String.eq(mode, "access-failure"), Fail{E.Operation{"access failed"}}, Done{Unit{}})

def read(environment: Stage, path: String) -> IO(E.ResultOf(List<&2, U32>)):
  match environment:
    case Stage{+mode, controller, calls}:
      do IO<E.ResultOf(List<&2, U32>)>:
        record(calls, "R")
        cancel(mode, "read", controller)
        return Bool.pick(E.ResultOf(List<&2, U32>), String.eq(mode, "read-failure"), Fail{E.Operation{"read failed"}}, Done{U.encode("hello")})

def write(environment: Stage, input: String & String) -> IO(E.ResultOf(Unit)):
  match environment input:
    case Stage{+mode, controller, calls} Tuple{_, content}:
      do IO<E.ResultOf(Unit)>:
        T.check(String.eq(content, "bye"), "injected write content")
        record(calls, "W")
        cancel(mode, "write", controller)
        return Bool.pick(E.ResultOf(Unit), String.eq(mode, "write-failure"), Fail{E.Operation{"write failed"}}, Done{Unit{}})

def outcome(mode: String, result: E.ToolResult()) -> IO(Unit):
  match mode result:
    case "read-failure" Fail{E.Operation{"read failed"}}: IO.pure(Unit, Unit{})
    case "write-failure" Fail{E.Operation{"write failed"}}: IO.pure(Unit, Unit{})
    case "success" Done{_}: IO.pure(Unit, Unit{})
    case _ Fail{E.Aborted{}}: IO.pure(Unit, Unit{})
    case _ Fail{error}: IO.die(Unit, 1, E.errorMessage(error))
    case _ _: IO.die(Unit, 1, "incorrect operation outcome")

def staged(+mode: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<Unit> <- A.new(Unit)
    +calls : R.Ref<String> <- R.new(String, "")
    +environment : Stage = Stage{mode, controller, calls}
    reader : C.Callback<String, E.ResultOf(List<&2, U32>)> <- C.create(~Stage, ~String, ~E.ResultOf(List<&2, U32>), ~read, environment)
    writer : C.Callback<(String & String), E.ResultOf(Unit)> <- C.create(~Stage, ~(String & String), ~E.ResultOf(Unit), ~write, environment)
    checker : C.Callback<String, E.ResultOf(Unit)> <- C.create(~Stage, ~String, ~E.ResultOf(Unit), ~access, environment)
    +operations : E.EditOperations = E.EditOperations{reader, writer, checker}
    ignored : Bool <- Bool.pick(IO(Bool), String.eq(mode, "before"), A.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    result : E.ToolResult() <- E.edit(operations, path, path, D.Edit{"hello", "bye"} <> Nil{}, Some{A.signal(Unit, controller)})
    outcome(mode, result)
    E.dispose(operations)
    A.dispose(Unit, controller)
    recorded : String <- R.dispose(String, calls)
    IO.print(recorded)

type Gate is Data:
  Gate{entered: Chan(Unit), resume: Chan(Unit), settled: R.Ref<Bool>}

def heldWrite(environment: Gate, input: String & String) -> IO(E.ResultOf(Unit)):
  match environment:
    case Gate{entered, resume, settled}:
      do IO<E.ResultOf(Unit)>:
        T.signal(entered)
        IO.join(Unit, resume)
        result : E.ResultOf(Unit) <- E.localWrite(Unit{}, input)
        R.write(Bool, settled, True{})
        return result

def afterEdit(settled: R.Ref<Bool>, input: String & String) -> IO(W.Outcome()):
  do IO<W.Outcome()>:
    finished : Bool <- R.read(Bool, settled)
    T.check(finished, "edit released queue before write settled")
    W.localWrite(Unit{}, input)

def writeSucceeded(value: W.Outcome()) -> IO(Unit):
  match value:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "successor write failed")

def retained(pair: Q.Owner & Q.Queue, +path: String, +alias: String) -> IO(Unit):
  match pair:
    case (owner, +queue):
      do IO<Unit>:
        +entered : Chan(Unit) <- Chan.new(Unit, 1)
        +resume : Chan(Unit) <- Chan.new(Unit, 1)
        +settled : R.Ref<Bool> <- R.new(Bool, False{})
        +controller : A.AbortController<Unit> <- A.new(Unit)
        reader : C.Callback<String, E.ResultOf(List<&2, U32>)> <- C.create(~Unit, ~String, ~E.ResultOf(List<&2, U32>), ~E.localRead, Unit{})
        writer : C.Callback<(String & String), E.ResultOf(Unit)> <- C.create(~Gate, ~(String & String), ~E.ResultOf(Unit), ~heldWrite, Gate{entered, resume, settled})
        checker : C.Callback<String, E.ResultOf(Unit)> <- C.create(~Unit, ~String, ~E.ResultOf(Unit), ~E.localAccess, Unit{})
        +operations : E.EditOperations = E.EditOperations{reader, writer, checker}
        first : Chan(E.ToolResult()) <- IO.fork(E.ToolResult(), E.execute(queue, operations, path, path, D.Edit{"hello", "bye"} <> Nil{}, Some{A.signal(Unit, controller)}))
        IO.join(Unit, entered)
        ignored : Bool <- A.abort(Unit, controller, None{})
        nextWriter : C.Callback<(String & String), W.Outcome()> <- C.create(~R.Ref<Bool>, ~(String & String), ~W.Outcome(), ~afterEdit, settled)
        mkdir : C.Callback<String, W.Outcome()> <- C.create(~Unit, ~String, ~W.Outcome(), ~W.localMkdir, Unit{})
        +next : W.WriteOperations = W.WriteOperations{nextWriter, mkdir}
        reservation : Result<&2, &1, FS.Error, Q.Reservation> <- Q.register(queue, alias)
        second : Chan(Result<&2, &1, FS.Error, W.Outcome()>) <- IO.fork(Result<&2, &1, FS.Error, W.Outcome()>, Q.execute(W.Outcome(), queue, _ => W.write(next, alias, "last", None{}), reservation))
        T.signal(resume)
        firstResult : E.ToolResult() <- IO.join(E.ToolResult(), first)
        outcome("write-abort", firstResult)
        secondResult : Result<&2, &1, FS.Error, W.Outcome()> <- IO.join(Result<&2, &1, FS.Error, W.Outcome()>, second)
        writeSucceeded(W.queued(secondResult))
        E.dispose(operations)
        W.dispose(next)
        A.dispose(Unit, controller)
        finished : Bool <- R.dispose(Bool, settled)
        T.check(finished, "edit never settled")
        Q.dispose(owner)
        IO.print("ok")

def parallel(pair: Q.Owner & Q.Queue, +path: String, +alias: String) -> IO(Unit):
  match pair:
    case (owner, +queue):
      do IO<Unit>:
        +operations : E.EditOperations <- E.defaultEditOperations()
        first : Chan(E.ToolResult()) <- IO.fork(E.ToolResult(), E.execute(queue, operations, path, path, D.Edit{"hello", "bye"} <> Nil{}, None{}))
        second : Chan(E.ToolResult()) <- IO.fork(E.ToolResult(), E.execute(queue, operations, alias, alias, D.Edit{"world", "there"} <> Nil{}, None{}))
        firstResult : E.ToolResult() <- IO.join(E.ToolResult(), first)
        secondResult : E.ToolResult() <- IO.join(E.ToolResult(), second)
        outcome("success", firstResult)
        outcome("success", secondResult)
        E.dispose(operations)
        Q.dispose(owner)
        IO.print("ok")

def run(args: List<String>) -> IO(Unit):
  match args:
    case "retained" <> path <> alias <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        retained(Q.borrow(owner), path, alias)
    case "parallel" <> path <> alias <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        parallel(Q.borrow(owner), path, alias)
    case mode <> path <> Nil{}: staged(mode, path)
    case _: IO.die(Unit, 1, "invalid operation fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
