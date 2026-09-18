import Base
import ./deferred.bend as D

# Cancellation is a one-shot effect. Its reason is an immutable value.
type AbortReason<-Reason: Data> is Data:
  Supplied{value: Reason}
  DefaultAbort{}

type AbortSignal<-Reason: Data> is Data:
  AbortSignal{settlement: D.Deferred<AbortReason<Reason>>}

type AbortController<-Reason: Data> is Data:
  AbortController{signal: AbortSignal<Reason>}

def new(-Reason: Data) -> IO(AbortController<Reason>):
  do IO<AbortController<Reason>>:
    settlement : D.Deferred<AbortReason<Reason>> <- D.new(AbortReason<Reason>)
    return AbortController{AbortSignal{settlement}}

def signal(-Reason: Data, controller: AbortController<Reason>) -> AbortSignal<Reason>:
  match controller:
    case AbortController{value}: value

def reason(-Reason: Data, value: AbortSignal<Reason>) -> IO(Maybe<&2, AbortReason<Reason>>):
  match value:
    case AbortSignal{settlement}: D.peek(AbortReason<Reason>, settlement)

def aborted(-Reason: Data, value: AbortSignal<Reason>) -> IO(Bool):
  do IO<Bool>:
    current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, value)
    return Bool.not(Maybe.is_none(&2, AbortReason<Reason>, current))

def checked(-Reason: Data, value: Maybe<&2, AbortReason<Reason>>) -> Result<&2, &2, AbortReason<Reason>, Unit>:
  match value:
    case None{}: Done{Unit{}}
    case Some{why}: Fail{why}

def throwIfAborted(-Reason: Data, value: AbortSignal<Reason>) -> IO(Result<&2, &2, AbortReason<Reason>, Unit>):
  do IO<Result<&2, &2, AbortReason<Reason>, Unit>>:
    current : Maybe<&2, AbortReason<Reason>> <- reason(Reason, value)
    return checked(Reason, current)

def suppliedReason(-Reason: Data, why: Maybe<&2, Reason>) -> AbortReason<Reason>:
  match why:
    case None{}: DefaultAbort{}
    case Some{value}: Supplied{value}

# The Boolean reports whether this caller won the atomic first settlement.
def abort(-Reason: Data, controller: AbortController<Reason>, why: Maybe<&2, Reason>) -> IO(Bool):
  match controller:
    case AbortController{AbortSignal{settlement}}: D.resolve(AbortReason<Reason>, settlement, suppliedReason(Reason, why))

# Registration is acknowledged before return. Late observers receive the stored
# reason. Cancelling an observation unlinks it without aborting the signal.
def observe(-Reason: Data, value: AbortSignal<Reason>) -> IO(D.Observation<AbortReason<Reason>>):
  match value:
    case AbortSignal{settlement}: D.observe(AbortReason<Reason>, settlement)

# The owner disposes the signal after all observation tickets have completed.
def dispose(-Reason: Data, controller: AbortController<Reason>) -> IO(Unit):
  match controller:
    case AbortController{AbortSignal{settlement}}: D.dispose(AbortReason<Reason>, settlement)
