import Base

# Shared identity with one owned value. Channels supply synchronization; all
# reference policy and operations are Bend. No actor or background task runs.
type Ref<-A: Type> is Data:
  Ref{channel: Chan(A)}

# Pure identity comparison, including affine contents; never reads the value.
def same(-A: Type, left: Ref<A>, right: Ref<A>) -> Bool:
  match left right:
    case Ref{a} Ref{b}: Chan.same(A, a, b)

def requireSent(sent: Bool) -> IO(Unit):
  match sent:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "Ref: backing channel closed")

def new(-A: Type, value: A) -> IO(Ref<A>):
  do IO<Ref<A>>:
    +channel : Chan(A) <- Chan.new(A, 1)
    sent : Bool <- Chan.send(A, channel, value)
    requireSent(sent)
    return Ref{channel}

def restore(-A: Type, -R: Type, channel: Chan(A), pair: A & R) -> IO(R):
  match pair:
    case Tuple{value, result}:
      do IO<R>:
        sent : Bool <- Chan.send(A, channel, value)
        requireSent(sent)
        return result

def modifyTaken(-A: Type, -R: Type, channel: Chan(A), transform: A -> A & R, taken: Maybe<&1, A>) -> IO(R):
  match taken:
    case None{}: IO.die(R, 1, "Ref: backing channel closed")
    case Some{value}: restore(A, R, channel, transform(value))

# A pure callback runs while the value is exclusively owned. Returning the
# next state before releasing ownership makes concurrent updates atomic.
def modify(-A: Type, -R: Type, reference: Ref<A>, transform: A -> A & R) -> IO(R):
  match reference:
    case Ref{+channel}:
      do IO<R>:
        taken : Maybe<&1, A> <- Chan.recv(A, channel)
        modifyTaken(A, R, channel, transform, taken)

# A late asynchronous completion may race with owner disposal. It can publish
# while the reference is live and quietly decline after the channel closes.
def tryModifyTaken(-A: Type, -R: Type, channel: Chan(A), transform: A -> A & R, taken: Maybe<&1,A>) -> IO(Maybe<&1,R>):
  match taken:
    case None{}: IO.pure(Maybe<&1,R>,None{})
    case Some{value}:
      do IO<Maybe<&1,R>>:
        result : R <- restore(A,R,channel,transform(value))
        return Some{result}
def tryModify(-A: Type, -R: Type, reference: Ref<A>, transform: A -> A & R) -> IO(Maybe<&1,R>):
  match reference:
    case Ref{+channel}:
      do IO<Maybe<&1,R>>:
        taken : Maybe<&1,A> <- Chan.recv(A,channel)
        tryModifyTaken(A,R,channel,transform,taken)

def updateTaken(-A: Type, -R: Type, channel: Chan(A), transform: A -> IO(A & R), taken: Maybe<&1, A>) -> IO(R):
  match taken:
    case None{}: IO.die(R, 1, "Ref: backing channel closed")
    case Some{value}:
      do IO<R>:
        pair : A & R <- transform(value)
        restore(A, R, channel, pair)

# An effectful update keeps the value exclusively owned until its operation
# returns the next state, so a read-effect-write sequence is atomic: other
# updates, modifications and reads of this reference wait. The operation must
# not access the same reference.
def update(-A: Type, -R: Type, reference: Ref<A>, transform: A -> IO(A & R)) -> IO(R):
  match reference:
    case Ref{+channel}:
      do IO<R>:
        taken : Maybe<&1, A> <- Chan.recv(A, channel)
        updateTaken(A, R, channel, transform, taken)

def tryUpdateTaken(-A: Type, -R: Type, channel: Chan(A), transform: A -> IO(A & R), taken: Maybe<&1,A>) -> IO(Maybe<&1,R>):
  match taken:
    case None{}: IO.pure(Maybe<&1,R>,None{})
    case Some{value}:
      do IO<Maybe<&1,R>>:
        pair : A & R <- transform(value)
        result : R <- restore(A,R,channel,pair)
        return Some{result}
def tryUpdate(-A: Type, -R: Type, reference: Ref<A>, transform: A -> IO(A & R)) -> IO(Maybe<&1,R>):
  match reference:
    case Ref{+channel}:
      do IO<Maybe<&1,R>>:
        taken : Maybe<&1,A> <- Chan.recv(A,channel)
        tryUpdateTaken(A,R,channel,transform,taken)

def copied(-A: Data, +value: A) -> A & A: (value, value)

# Only Data can be copied out. Affine state is accessed through modify.
def read(-A: Data, reference: Ref<A>) -> IO(A):
  modify(A, A, reference, value => copied(A, value))

def write(-A: Type, reference: Ref<A>, value: A) -> IO(Unit):
  modify(A, Unit, reference, old => (value, Unit{}))

def swap(-A: Type, reference: Ref<A>, value: A) -> IO(A):
  modify(A, A, reference, old => (value, old))

def disposeTaken(-A: Type, channel: Chan(A), taken: Maybe<&1, A>) -> IO(A):
  match taken:
    case None{}: IO.die(A, 1, "Ref: backing channel closed")
    case Some{value}:
      do IO<A>:
        Chan.close(A, channel)
        return value

# The owner must retire all aliases before disposal. Return the affine value
# so resources inside it can be released by their owner rather than lost.
def dispose(-A: Type, reference: Ref<A>) -> IO(A):
  match reference:
    case Ref{+channel}:
      do IO<A>:
        taken : Maybe<&1, A> <- Chan.recv(A, channel)
        disposeTaken(A, channel, taken)
