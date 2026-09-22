import Base
import ../packages/coding-agent/src/core/tools/write.bend as W
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Q
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ./file-mutation-queue.bend as T

type Controlled is Data:
  Controlled{entered: Chan(Unit), resume: Chan(Unit), settled: R.Ref<Bool>}

def success(value: W.Outcome()) -> IO(Unit):
  match value:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "write failed")

def aborted(value: W.Outcome()) -> IO(Unit):
  match value:
    case Fail{W.Aborted{}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "write did not report cancellation")

def controlled(environment: Controlled, input: String & String) -> IO(W.Outcome()):
  match environment input:
    case Controlled{entered, resume, settled} Tuple{+path, "first"}:
      do IO<W.Outcome()>:
        T.signal(entered)
        IO.join(Unit, resume)
        value : W.Outcome() <- W.localWrite(Unit{}, (path, "first"))
        R.write(Bool, settled, True{})
        return value
    case Controlled{_, _, settled} pair:
      do IO<W.Outcome()>:
        finished : Bool <- R.read(Bool, settled)
        T.check(finished, "aborted write released queue before settling")
        W.localWrite(Unit{}, pair)

def inflight(ownership: Q.Owner & Q.Queue, +path: String) -> IO(Unit):
  match ownership:
    case (owner, +queue):
      do IO<Unit>:
        +entered : Chan(Unit) <- Chan.new(Unit, 1)
        +resume : Chan(Unit) <- Chan.new(Unit, 1)
        +settled : R.Ref<Bool> <- R.new(Bool, False{})
        +controller : A.AbortController<Unit> <- A.new(Unit)
        write : C.Callback<(String & String), W.Outcome()> <- C.create(~Controlled, ~(String & String), ~W.Outcome(), ~controlled, Controlled{entered, resume, settled})
        mkdir : C.Callback<String, W.Outcome()> <- C.create(~Unit, ~String, ~W.Outcome(), ~W.localMkdir, Unit{})
        +operations : W.WriteOperations = W.WriteOperations{write, mkdir}
        first : Chan(W.Outcome()) <- IO.fork(W.Outcome(), W.execute(queue, operations, path, "first", Some{A.signal(Unit, controller)}))
        IO.join(Unit, entered)
        cancelled : Bool <- A.abort(Unit, controller, None{})
        T.check(cancelled, "abort controller did not settle")
        reservation : Result<&2, &1, FS.Error, Q.Reservation> <- Q.register(queue, path)
        second : Chan(Result<&2, &1, FS.Error, W.Outcome()>) <- IO.fork(Result<&2, &1, FS.Error, W.Outcome()>, Q.execute(W.Outcome(), queue, _ => W.write(operations, path, "second", None{}), reservation))
        T.signal(resume)
        firstResult : W.Outcome() <- IO.join(W.Outcome(), first)
        aborted(firstResult)
        secondResult : Result<&2, &1, FS.Error, W.Outcome()> <- IO.join(Result<&2, &1, FS.Error, W.Outcome()>, second)
        success(W.queued(secondResult))
        W.dispose(operations)
        A.dispose(Unit, controller)
        finished : Bool <- R.dispose(Bool, settled)
        T.check(finished, "write never settled")
        Q.dispose(owner)
        IO.print("ok")

def local(ownership: Q.Owner & Q.Queue, path: String, content: String, +cancel: Bool) -> IO(Unit):
  match ownership:
    case (owner, queue):
      do IO<Unit>:
        +operations : W.WriteOperations <- W.defaultWriteOperations()
        +controller : A.AbortController<Unit> <- A.new(Unit)
        ignored : Bool <- Bool.pick(IO(Bool), cancel, A.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
        result : W.Outcome() <- W.execute(queue, operations, path, content, Some{A.signal(Unit, controller)})
        Bool.pick(W.Outcome() -> IO(Unit), cancel, aborted, success)(result)
        W.dispose(operations)
        A.dispose(Unit, controller)
        Q.dispose(owner)
        IO.print("ok")

type Stage is Data:
  Stage{mode: String, controller: A.AbortController<Unit>}

def stageMkdir(environment: Stage, path: String) -> IO(W.Outcome()):
  match environment:
    case Stage{+mode, controller}:
      do IO<W.Outcome()>:
        made : W.Outcome() <- W.localMkdir(Unit{}, path)
        success(made)
        ignored : Bool <- Bool.pick(IO(Bool), String.eq(mode, "mkdir-abort") || String.eq(mode, "mkdir-failure"), A.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
        return Bool.pick(W.Outcome(), String.eq(mode, "mkdir-failure"), Fail{W.Operation{"mkdir failed"}}, Done{Unit{}})

def stageWrite(environment: Stage, input: String & String) -> IO(W.Outcome()):
  match environment:
    case Stage{+mode, controller}:
      do IO<W.Outcome()>:
        written : W.Outcome() <- W.localWrite(Unit{}, input)
        success(written)
        ignored : Bool <- A.abort(Unit, controller, None{})
        return Bool.pick(W.Outcome(), String.eq(mode, "write-failure"), Fail{W.Operation{"write failed"}}, Done{Unit{}})

def stageResult(mode: String, result: W.Outcome()) -> IO(Unit):
  match mode result:
    case "mkdir-failure" Fail{W.Operation{"mkdir failed"}}: IO.pure(Unit, Unit{})
    case "write-failure" Fail{W.Operation{"write failed"}}: IO.pure(Unit, Unit{})
    case "mkdir-abort" Fail{W.Aborted{}}: IO.pure(Unit, Unit{})
    case "write-abort" Fail{W.Aborted{}}: IO.pure(Unit, Unit{})
    case _ _: IO.die(Unit, 1, "wrong stage error precedence")

def staged(ownership: Q.Owner & Q.Queue, +mode: String, path: String) -> IO(Unit):
  match ownership:
    case (owner, queue):
      do IO<Unit>:
        +controller : A.AbortController<Unit> <- A.new(Unit)
        writer : C.Callback<(String & String), W.Outcome()> <- C.create(~Stage, ~(String & String), ~W.Outcome(), ~stageWrite, Stage{mode, controller})
        mkdir : C.Callback<String, W.Outcome()> <- C.create(~Stage, ~String, ~W.Outcome(), ~stageMkdir, Stage{mode, controller})
        +operations : W.WriteOperations = W.WriteOperations{writer, mkdir}
        result : W.Outcome() <- W.execute(queue, operations, path, "written", Some{A.signal(Unit, controller)})
        stageResult(mode, result)
        W.dispose(operations)
        A.dispose(Unit, controller)
        Q.dispose(owner)
        IO.print("ok")

def run(args: List<String>) -> IO(Unit):
  match args:
    case "stage" <> mode <> path <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        staged(Q.borrow(owner), mode, path)
    case "inflight" <> path <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        inflight(Q.borrow(owner), path)
    case mode <> path <> content <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        local(Q.borrow(owner), path, content, String.eq(mode, "cancel"))
    case _: IO.die(Unit, 1, "invalid write fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
