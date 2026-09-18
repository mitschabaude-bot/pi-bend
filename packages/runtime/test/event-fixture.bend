import Base
import ../src/event.bend as E
import ../src/f64.bend as F
import ../src/u64.bend as W
import ../src/utf16.bend as U

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def equalBool(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def target(+value: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_eq(value, 0), None{}, Some{value})

def equalTarget(left: Maybe<&2, U32>, right: Maybe<&2, U32>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: U32.is_eq(a, b)
    case _ _: False{}

def equalPath(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: U32.is_eq(a, b) && equalPath(xs, ys)
    case _ _: False{}

def equalProperties(left: E.Properties<U32>, right: E.Properties<U32>) -> Bool:
  match left right:
    case E.Properties{at, ab, ac, ao, ad, astamp, ata, act, asrc, aph, acb, arv, atr, apath} E.Properties{bt, bb, bc, bo, bd, bstamp, bta, bct, bsrc, bph, bcb, brv, btr, bpath}:
      U.equal(at, bt) && equalBool(ab, bb) && equalBool(ac, bc) && equalBool(ao, bo) && equalBool(ad, bd) && W.equal(F.toBits(astamp), F.toBits(bstamp)) && equalTarget(ata, bta) && equalTarget(act, bct) && equalTarget(asrc, bsrc) && U32.is_eq(aph, bph) && equalBool(acb, bcb) && equalBool(arv, brv) && equalBool(atr, btr) && equalPath(apath, bpath)

def check(event: E.WebEvent<U32>, expected: E.Properties<U32>, label: String) -> IO(Unit):
  do IO<Unit>:
    actual : E.Properties<U32> <- E.snapshot(U32, event)
    assertion(equalProperties(actual, expected), label)

def requireBegin(result: Result<&2, &2, E.DispatchError, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "initial dispatch unexpectedly failed")

def begin(event: E.WebEvent<U32>, target: U32) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(U32, event, target)
    requireBegin(result)

def requireError(result: Result<&2, &2, E.DispatchError, Unit>, name: String, code: String, message: String) -> IO(Unit):
  match result:
    case Done{_}: IO.die(Unit, 1, "recursive dispatch unexpectedly succeeded")
    case Fail{+error}: assertion(String.eq(E.errorName(error), name) && String.eq(E.errorCode(error), code) && String.eq(E.recursionMessage(error), message), "recursive dispatch error differs from Node")

def recursive(event: E.WebEvent<U32>, name: String, code: String, message: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, E.DispatchError, Unit> <- E.beginDispatch(U32, event, 2)
    requireError(result, name, code, message)

def dispatchResult(event: E.WebEvent<U32>, expected: Bool) -> IO(Unit):
  do IO<Unit>:
    actual : Bool <- E.returnValue(U32, event)
    assertion(equalBool(actual, expected), "dispatch return value differs from Node")
