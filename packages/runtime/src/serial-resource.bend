import Base
import ./ref.bend as Ref

# The handle schedules access; the affine owner controls retirement. A single
# channel token owns the resource across an entire asynchronous operation.
type Handle<-A: Type> is Data:
  Handle{channel: Chan(A)}

type Owner<-A: Type> is Type:
  Owner{handle: Handle<A>}

def create(-A: Type, value: A) -> IO(Owner<A>):
  do IO<Owner<A>>:
    +channel : Chan(A) <- Chan.new(A, 1)
    sent : Bool <- Chan.send(A, channel, value)
    Ref.requireSent(sent)
    return Owner{Handle{channel}}

def borrow(-A: Type, owner: Owner<A>) -> Owner<A> & Handle<A>:
  match owner:
    case Owner{+handle}: (Owner{handle}, handle)

def restored(-A: Type, -B: Type, channel: Chan(A), result: A & B) -> IO(B):
  Ref.restore(A, B, channel, result)

def taken(-A: Type, -B: Type, channel: Chan(A), operation: A -> IO(A & B), value: Maybe<&1, A>) -> IO(B):
  match value:
    case None{}: IO.die(B, 1, "Serial resource: used after retirement")
    case Some{resource}:
      do IO<B>:
        result : A & B <- operation(resource)
        restored(A, B, channel, result)

# Typed failures are returned in B alongside the successor A, releasing the
# next queued operation. Operations must not await re-entry on their own handle.
def run(-A: Type, -B: Type, handle: Handle<A>, operation: A -> IO(A & B)) -> IO(B):
  match handle:
    case Handle{+channel}:
      do IO<B>:
        value : Maybe<&1, A> <- Chan.recv(A, channel)
        taken(A, B, channel, operation, value)

# Finish queued work and retire all handle aliases before calling this. The
# returned affine resource still belongs to the caller and must be closed.
def retire(-A: Type, owner: Owner<A>) -> IO(A):
  match owner:
    case Owner{Handle{+channel}}:
      do IO<A>:
        value : Maybe<&1, A> <- Chan.recv(A, channel)
        Ref.disposeTaken(A, channel, value)
