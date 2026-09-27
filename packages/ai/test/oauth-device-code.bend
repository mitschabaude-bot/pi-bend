import Base
import ../src/auth/oauth/device-code.bend as Device
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/timer.bend as Timer

# pi-mono f07218c4d packages/ai/test/oauth-device-code.test.ts. Upstream
# drives pollOAuthDeviceCodeFlow with fake timers and checks the exact poll
# times; here the flow runs on the real clock and each poll's offset from the
# start must fall in [expected, expected + 750 ms). "Not yet polled at
# expected - 1 ms" is the lower bound of that window.
def Result_() -> Data: Device.OAuthDeviceCodePollResult<String>

type Script is Data:
  Script{times: Ref.Ref<List<&2, F64>>, results: Ref.Ref<List<&2, Result_()>>}

def popped(results: List<&2, Result_()>) -> List<&2, Result_()> & Result_():
  match results:
    case Nil{}: (Nil{}, Device.PollPending{})
    case first <> rest: (rest, first)

def appended(+now: F64, times: List<&2, F64>) -> List<&2, F64> & Unit: (List.reverse(&2, F64, now <> List.reverse(&2, F64, times)), Unit{})

def polled(script: Script, input: Unit) -> IO(Result_()):
  match script:
    case Script{times, results}:
      do IO<Result_()>:
        now : F64 <- Date.now()
        recorded : Unit <- Ref.modify(List<&2, F64>, Unit, times, current => appended(now, current))
        Ref.modify(List<&2, Result_()>, Result_(), results, popped)

def pollerOf(script: Script) -> IO(C.Callback<Unit, Result_()>): C.create(~Script, ~Unit, ~Result_(), ~polled, script)

def offsets(+start: F64, times: List<&2, F64>) -> List<&2, F64>:
  match times:
    case Nil{}: Nil{}
    case time <> rest: F.subtract(time, start) <> offsets(start, rest)

def within(+offset: F64, +expected: U32) -> Bool:
  F.isGreater(F.compare(F.add(offset, F.fromU32(1)), F.fromU32(expected))) && F.isGreater(F.compare(F.fromU32((expected + 750 : U32)), offset))

def matched(offsets: List<&2, F64>, expected: List<&2, U32>) -> Bool:
  match offsets expected:
    case Nil{} Nil{}: True{}
    case offset <> rest wanted <> others: within(offset, wanted) && matched(rest, others)
    case _ _: False{}

def shownOffsets(values: List<&2, F64>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: U32.show(F64.to_u32(F64.floor(value))) ++ " " ++ shownOffsets(rest)

def resultText(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{value}: "value " ++ value
    case Fail{message}: "error " ++ message

def check(+name: String, ok: Bool, detail: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.print("PASS " ++ name), IO.print("FAIL " ++ name ++ ": " ++ detail))

def timed(name: String, interval: U32, expires: U32, wait: Bool, script: List<&2, Result_()>, expected: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    +times : Ref.Ref<List<&2, F64>> <- Ref.new(List<&2, F64>, Nil{})
    results : Ref.Ref<List<&2, Result_()>> <- Ref.new(List<&2, Result_()>, script)
    poller : C.Callback<Unit, Result_()> <- pollerOf(Script{times, results})
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +start : F64 <- Date.now()
    +result : Result<&2, &2, String, String> <- Device.pollOAuthDeviceCodeFlow(~String, Device.OAuthDeviceCodePollOptions{Some{F.fromU32(interval)}, Some{F.fromU32(expires)}, wait, poller, Abort.signal(Unit, controller)})
    +seen : List<&2, F64> <- Ref.read(List<&2, F64>, times)
    +shifted : List<&2, F64> <- IO.pure(List<&2, F64>, offsets(start, seen))
    check(name, String.eq(resultText(result), "value token") && matched(shifted, expected), resultText(result) ++ "; poll offsets " ++ shownOffsets(shifted))

def pending() -> Result_(): Device.PollPending{}
def complete() -> Result_(): Device.PollComplete{"token"}

def abortLater(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +quiet : Abort.AbortController<Unit> <- Abort.new(Unit)
    slept : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Timer.sleep(Unit, 200, Abort.signal(Unit, quiet))
    won : Bool <- Abort.abort(Unit, controller, None{})
    return Unit{}

def cancelled() -> IO(Unit):
  do IO<Unit>:
    times : Ref.Ref<List<&2, F64>> <- Ref.new(List<&2, F64>, Nil{})
    results : Ref.Ref<List<&2, Result_()>> <- Ref.new(List<&2, Result_()>, Nil{})
    poller : C.Callback<Unit, Result_()> <- pollerOf(Script{times, results})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    task : Chan(Unit) <- IO.fork(Unit, abortLater(controller))
    +result : Result<&2, &2, String, String> <- Device.pollOAuthDeviceCodeFlow(~String, Device.OAuthDeviceCodePollOptions{Some{F.fromU32(5)}, Some{F.fromU32(30)}, False{}, poller, Abort.signal(Unit, controller)})
    joined : Unit <- IO.join(Unit, task)
    check("cancels an in-flight wait", String.eq(resultText(result), "error Login cancelled"), resultText(result))

def run() -> IO(Unit):
  do IO<Unit>:
    timed("polls immediately and returns the completed value", 2, 30, False{}, {[pending(), complete()] : List<&2, Result_()>}, {[0, 2000] : List<&2, U32>})
    timed("can wait before the first poll", 2, 30, True{}, {[complete()] : List<&2, Result_()>}, {[2000] : List<&2, U32>})
    timed("increases the interval by 5 seconds after slow_down without a server interval", 2, 900, False{}, {[Device.PollSlowDown{None{}}, complete()] : List<&2, Result_()>}, {[0, 7000] : List<&2, U32>})
    timed("honors a server-provided slow_down interval", 2, 900, False{}, {[Device.PollSlowDown{Some{F.fromU32(30)}}, complete()] : List<&2, Result_()>}, {[0, 30000] : List<&2, U32>})
    cancelled()

def main() -> IO(Unit): run()
