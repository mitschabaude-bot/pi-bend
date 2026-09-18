import Base
import ../src/event.bend as E
import ../src/ref.bend as R
import ../src/f64.bend as F
import ../src/u64.bend as W
import ../src/utf16.bend as U

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def started(value: Result<&2, &2, E.DispatchError, Unit>) -> Bool:
  match value:
    case Done{_}: True{}
    case Fail{_}: False{}

def rejected(value: Result<&2, &2, E.DispatchError, Unit>) -> Bool:
  match value:
    case Fail{error}: String.eq(E.errorCode(error), "ERR_EVENT_RECURSION")
    case _: False{}

def sameTarget(value: Maybe<&2, R.Ref<String>>, expected: R.Ref<String>) -> Bool:
  match value:
    case Some{target}: R.same(String, target, expected)
    case None{}: False{}

def targetText(value: Maybe<&2, R.Ref<String>>) -> IO(String):
  match value:
    case Some{target}: R.read(String, target)
    case None{}: IO.die(String, 1, "missing event target")

def samePath(value: List<&2, R.Ref<String>>, expected: R.Ref<String>) -> Bool:
  match value:
    case target <> Nil{}: R.same(String, target, expected)
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +first : R.Ref<String> <- R.new(String, "before")
    +second : R.Ref<String> <- R.new(String, "other")
    +event : E.WebEvent<R.Ref<String>> <- E.createAt(R.Ref<String>, "🐱", E.EventInit{True{}, True{}, True{}}, F.fromBits(1072693248, 1), False{})
    +holder : R.Ref<E.WebEvent<R.Ref<String>>> <- R.new(E.WebEvent<R.Ref<String>>, event)
    +alias : E.WebEvent<R.Ref<String>> <- R.read(E.WebEvent<R.Ref<String>>, holder)
    assertion(E.same(R.Ref<String>, event, alias), "event aliases must have shared identity")
    initial : Maybe<&2, R.Ref<String>> <- E.target(R.Ref<String>, event)
    assertion(Maybe.is_none(&2, R.Ref<String>, initial), "new event has null target")
    name : String <- E.eventType(R.Ref<String>, event)
    assertion(U.equal(name, U.unit(55357) ++ U.unit(56369)), "event type must retain UTF-16 identity")
    result : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(R.Ref<String>, event, first)
    assertion(started(result), "initial dispatch")
    result : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(R.Ref<String>, alias, second)
    assertion(rejected(result), "recursive dispatch must reject without replacing target")
    target : Maybe<&2, R.Ref<String>> <- E.target(R.Ref<String>, alias)
    assertion(sameTarget(target, first), "rejected recursive dispatch changed target identity")
    target : Maybe<&2, R.Ref<String>> <- E.currentTarget(R.Ref<String>, alias)
    assertion(sameTarget(target, first), "active currentTarget must retain the actual target")
    targets : List<&2, R.Ref<String>> <- E.composedPath(R.Ref<String>, alias)
    assertion(samePath(targets, first), "active path must contain the original target handle")
    R.write(String, first, "after")
    target : Maybe<&2, R.Ref<String>> <- E.srcElement(R.Ref<String>, event)
    value : String <- targetText(target)
    assertion(String.eq(value, "after"), "event target must be a live object, not a copied value")
    E.enterListener(R.Ref<String>, event, True{})
    E.preventDefault(R.Ref<String>, alias)
    cancelled : Bool <- E.defaultPrevented(R.Ref<String>, event)
    assertion(Bool.not(cancelled), "passive listener must not cancel")
    # Simulate a throwing callback: leaveListener runs but listenerReturned does not.
    E.leaveListener(R.Ref<String>, event)
    phase : U32 <- E.eventPhase(R.Ref<String>, alias)
    assertion(U32.is_eq(phase, E.AT_TARGET()), "listener throw must not run successful-return cleanup")
    result : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(R.Ref<String>, alias, second)
    assertion(rejected(result), "dispatch guard must remain after a throwing listener")
    E.finishDispatch(R.Ref<String>, event)
    E.preventDefault(R.Ref<String>, event)
    cancelled : Bool <- E.defaultPrevented(R.Ref<String>, alias)
    assertion(cancelled, "passive cleanup must permit later cancellation")
    result : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(R.Ref<String>, event, second)
    assertion(started(result), "finished event must support redispatch")
    E.listenerReturned(R.Ref<String>, event)
    E.enterListener(R.Ref<String>, event, False{})
    phase : U32 <- E.eventPhase(R.Ref<String>, alias)
    assertion(U32.is_eq(phase, E.NONE()), "later listener must not restore Node's cleared dispatch flag")
    current : Maybe<&2, R.Ref<String>> <- E.currentTarget(R.Ref<String>, event)
    assertion(Maybe.is_none(&2, R.Ref<String>, current), "cleared dispatch flag must hide currentTarget")
    target : Maybe<&2, R.Ref<String>> <- E.target(R.Ref<String>, alias)
    assertion(sameTarget(target, second), "redispatch must retain its new target after callback return")
    E.stopImmediatePropagation(R.Ref<String>, event)
    E.setCancelBubble(R.Ref<String>, event, False{})
    E.initEvent(R.Ref<String>, alias, "renamed", False{}, False{})
    immediate : Bool <- E.immediatePropagationStopped(R.Ref<String>, event)
    stopped : Bool <- E.cancelBubble(R.Ref<String>, alias)
    assertion(immediate && stopped, "initEvent and cancelBubble=false must not reset stop flags")
    stamp : F.F64 <- E.timeStamp(R.Ref<String>, event)
    assertion(W.equal(F.toBits(stamp), W.U64{1072693248, 1}), "event timestamp must retain exact binary64 precision")
    trusted : Bool <- E.isTrusted(R.Ref<String>, event)
    assertion(Bool.not(trusted), "public event trust must remain false")
    E.finishDispatch(R.Ref<String>, alias)
    previous : E.WebEvent<R.Ref<String>> <- R.dispose(E.WebEvent<R.Ref<String>>, holder)
    E.dispose(R.Ref<String>, event)
    text : String <- R.read(String, first)
    assertion(String.eq(text, "after"), "disposing an event must not dispose caller-owned targets")
    previous : String <- R.dispose(String, first)
    previous : String <- R.dispose(String, second)
    IO.print("PASS Event identity, live targets, redispatch, throw cleanup and exact timestamps")
