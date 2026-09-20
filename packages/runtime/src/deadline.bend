import Base
import ./abort.bend as Abort
import ./deferred.bend as Deferred

# Distinguish an inherited abort (including its default reason) from expiry.
type Cause<-Reason: Data> is Data:
  ParentAbort{reason: Abort.AbortReason<Reason>}
  Expired{}

type Lifetime<-Reason: Data> is Type:
  Lifetime{timer: TimerCancel, observation: Deferred.Cancellation<Abort.AbortReason<Reason>>, parentTask: Chan(Unit), timerTask: Chan(Unit)}

type Scope<-Reason: Data> is Type:
  Scope{controller: Abort.AbortController<Cause<Reason>>, lifetime: Maybe<&1, Lifetime<Reason>>}

def inherited(-Reason: Data, controller: Abort.AbortController<Cause<Reason>>, value: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{why}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Cause<Reason>, controller, Some{ParentAbort{why}})
        return Unit{}

def parentReady(-Reason: Data, controller: Abort.AbortController<Cause<Reason>>, handle: TimerCancel, value: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{why}:
      do IO<Unit>:
        cancelled : Bool <- Timer.cancel(handle)
        inherited(Reason, controller, Some{why})

def watchParent(-Reason: Data, controller: Abort.AbortController<Cause<Reason>>, handle: TimerCancel, ticket: Deferred.Ticket<Maybe<&2, Abort.AbortReason<Reason>>>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2, Abort.AbortReason<Reason>> <- Deferred.wait(Maybe<&2, Abort.AbortReason<Reason>>, ticket)
    parentReady(Reason, controller, handle, value)

def expired(-Reason: Data, elapsed: Bool, controller: Abort.AbortController<Cause<Reason>>) -> IO(Unit):
  match elapsed:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Cause<Reason>, controller, Some{Expired{}})
        return Unit{}

def timerFinished(-Reason: Data, controller: Abort.AbortController<Cause<Reason>>, result: Timer & Bool) -> IO(Unit):
  match result:
    case (owner, elapsed):
      do IO<Unit>:
        Timer.close(owner)
        expired(Reason, elapsed, controller)

def watchTimer(-Reason: Data, controller: Abort.AbortController<Cause<Reason>>, owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    timerFinished(Reason, controller, result)

def observing(-Reason: Data, +controller: Abort.AbortController<Cause<Reason>>, observation: Deferred.Observation<Abort.AbortReason<Reason>>, pair: Timer & TimerCancel) -> IO(Scope<Reason>):
  match observation pair:
    case Deferred.Observation{ticket, cancellation} Tuple{owner, +handle}:
      do IO<Scope<Reason>>:
        parentTask : Chan(Unit) <- IO.fork(Unit, watchParent(Reason, controller, handle, ticket))
        timerTask : Chan(Unit) <- IO.fork(Unit, watchTimer(Reason, controller, owner))
        return Scope{controller, Some{Lifetime{handle, cancellation, parentTask, timerTask}}}

def checked(-Reason: Data, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +controller: Abort.AbortController<Cause<Reason>>, value: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Scope<Reason>):
  match value:
    case Some{why}:
      do IO<Scope<Reason>>:
        inherited(Reason, controller, Some{why})
        return Scope{controller, None{}}
    case None{}:
      do IO<Scope<Reason>>:
        observation : Deferred.Observation<Abort.AbortReason<Reason>> <- Abort.observe(Reason, parent)
        timer : Timer & TimerCancel <- Timer.new(milliseconds)
        observing(Reason, controller, observation, timer)

# The deadline begins at Timer.new and uses literal milliseconds, including
# zero. A parent already aborted at the initial check wins without any timer.
# Otherwise parent forwarding and expiry compete through first-settlement.
def create(-Reason: Data, milliseconds: U32, +parent: Abort.AbortSignal<Reason>) -> IO(Scope<Reason>):
  do IO<Scope<Reason>>:
    value : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
    controller : Abort.AbortController<Cause<Reason>> <- Abort.new(Cause<Reason>)
    checked(Reason, milliseconds, parent, controller, value)

# The signal is borrowed: users finish their operations/observations before
# closing this scope. The caller continues owning the parent signal.
def borrow(-Reason: Data, scope: Scope<Reason>) -> Scope<Reason> & Abort.AbortSignal<Cause<Reason>>:
  match scope:
    case Scope{+controller, lifetime}: (Scope{controller, lifetime}, Abort.signal(Cause<Reason>, controller))

def retire(-Reason: Data, lifetime: Maybe<&1, Lifetime<Reason>>) -> IO(Unit):
  match lifetime:
    case None{}: IO.pure(Unit, Unit{})
    case Some{Lifetime{handle, cancellation, parentTask, timerTask}}:
      do IO<Unit>:
        cancelled : Bool <- Timer.cancel(handle)
        removed : Bool <- Deferred.cancel(Abort.AbortReason<Reason>, cancellation)
        IO.join(Unit, parentTask)
        IO.join(Unit, timerTask)
        return Unit{}

# Always close, including after expiry/parent abort. Stop unused background
# work, join both tasks, then dispose the child signal. Return its immutable
# settled reason; expiry racing with close may legitimately have won already.
def close(-Reason: Data, scope: Scope<Reason>) -> IO(Maybe<&2, Abort.AbortReason<Cause<Reason>>>):
  match scope:
    case Scope{+controller, lifetime}:
      do IO<Maybe<&2, Abort.AbortReason<Cause<Reason>>>>:
        retire(Reason, lifetime)
        reason : Maybe<&2, Abort.AbortReason<Cause<Reason>>> <- Abort.reason(Cause<Reason>, Abort.signal(Cause<Reason>, controller))
        Abort.dispose(Cause<Reason>, controller)
        return reason
