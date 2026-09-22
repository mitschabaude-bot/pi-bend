import Base
import ./file-mutation-queue.bend as Queue
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/string.bend as Strings

# The filesystem execution core of write.ts. Tool-definition metadata, schema
# decoding, input path normalization and renderers are added at the public boundary.
type WriteToolInput is Data:
  WriteToolInput{path: String, content: String}

type Error is Data:
  Filesystem{cause: FS.Error}
  Operation{message: String}
  Aborted{}

def Outcome() -> Data: Result<&2, &2, Error, Unit>

type WriteOperations is Data:
  WriteOperations{writeFile: Callback.Callback<(String & String), Outcome()>, mkdir: Callback.Callback<String, Outcome()>}

def filesystem(result: Result<&2, &2, FS.Error, Unit>) -> Outcome():
  match result:
    case Done{value}: Done{value}
    case Fail{cause}: Fail{Filesystem{cause}}

def localWrite(environment: Unit, input: String & String) -> IO(Outcome()):
  match input:
    case (path, content):
      do IO<Outcome()>:
        value : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, content)
        return filesystem(value)

def localMkdir(environment: Unit, path: String) -> IO(Outcome()):
  do IO<Outcome()>:
    value : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(path)
    return filesystem(value)

def defaultWriteOperations() -> IO(WriteOperations):
  do IO<WriteOperations>:
    writer : Callback.Callback<(String & String), Outcome()> <- Callback.create(~Unit, ~(String & String), ~Outcome(), ~localWrite, Unit{})
    mkdir : Callback.Callback<String, Outcome()> <- Callback.create(~Unit, ~String, ~Outcome(), ~localMkdir, Unit{})
    return WriteOperations{writer, mkdir}

# The owner retires callbacks only after every invocation has settled.
def dispose(operations: WriteOperations) -> IO(Unit):
  match operations:
    case WriteOperations{writer, mkdir}:
      do IO<Unit>:
        Callback.dispose(String & String, Outcome(), writer)
        Callback.dispose(String, Outcome(), mkdir)

def cancellation(aborted: Bool) -> Outcome():
  match aborted:
    case True{}: Fail{Aborted{}}
    case False{}: Done{Unit{}}

def check(signal: Maybe<&2, Abort.AbortSignal<Unit>>, previous: Outcome()) -> IO(Outcome()):
  match signal previous:
    case _ Fail{error}: IO.pure(Outcome(), Fail{error})
    case None{} Done{Unit{}}: IO.pure(Outcome(), Done{Unit{}})
    case Some{value} Done{Unit{}}:
      do IO<Outcome()>:
        aborted : Bool <- Abort.aborted(Unit, value)
        return cancellation(aborted)

# Paths reaching this core have already been normalized to absolute paths.
def parentParts(parts: List<&2, String>) -> String:
  match parts:
    case _ <> "" <> Nil{}: "/"
    case _ <> rest: String.join(List.reverse(&2, String, rest), "/")
    case Nil{}: "/"

def parent(path: String) -> String:
  parentParts(List.reverse(&2, String, Strings.split(path, '/')))

def makeDirectory(callback: Callback.Callback<String, Outcome()>, path: String, previous: Outcome()) -> IO(Outcome()):
  match previous:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{Unit{}}: Callback.call(String, Outcome(), callback, path)

def writeFile(callback: Callback.Callback<(String & String), Outcome()>, path: String, content: String, previous: Outcome()) -> IO(Outcome()):
  match previous:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{Unit{}}: Callback.call(String & String, Outcome(), callback, (path, content))

def write(operations: WriteOperations, +absolutePath: String, content: String, +signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Outcome()):
  match operations:
    case WriteOperations{writer, mkdir}:
      do IO<Outcome()>:
        before : Outcome() <- check(signal, Done{Unit{}})
        made : Outcome() <- makeDirectory(mkdir, parent(absolutePath), before)
        ready : Outcome() <- check(signal, made)
        written : Outcome() <- writeFile(writer, absolutePath, content, ready)
        check(signal, written)

def queued(result: Result<&2, &1, FS.Error, Outcome()>) -> Outcome():
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: value

# No cancellation race detaches filesystem work. Queue ownership lasts until
# write returns, including a write that finishes after cancellation was requested.
def execute(queue: Queue.Queue, operations: WriteOperations, +absolutePath: String, content: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Outcome()):
  do IO<Outcome()>:
    value : Result<&2, &1, FS.Error, Outcome()> <- Queue.withFileMutationQueue(Outcome(), queue, absolutePath, _ => write(operations, absolutePath, content, signal))
    return queued(value)
