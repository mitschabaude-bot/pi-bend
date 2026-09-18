import Base
import ../../src/api/constrained-sampling.bend as C
import ../../../runtime/src/utf16.bend as U
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/test/schema.bend as Assert

type Step is Data:
  Step{property: String, next: String, close: Bool, expected: Result<&2, &2, String, Maybe<&2, String>>, buffer: C.GrammarToolInputJsonBuffer}

def sameBool(+left: Bool, +right: Bool) -> Bool: (left && right) || (Bool.not(left) && Bool.not(right))

def sameBuffer(left: C.GrammarToolInputJsonBuffer, right: C.GrammarToolInputJsonBuffer) -> Bool:
  match left right:
    case C.GrammarToolInputJsonBuffer{a,b,c} C.GrammarToolInputJsonBuffer{x,y,z}: U.equal(a,x) && sameBool(b,y) && sameBool(c,z)

def sameDelta(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: U.equal(a,b)
    case _ _: False{}

def checked(result: Result<&2, &2, C.Error, C.GrammarToolInputJsonUpdate>, +previous: C.GrammarToolInputJsonBuffer, expected: Result<&2, &2, String, Maybe<&2, String>>, buffer: C.GrammarToolInputJsonBuffer, label: String) -> IO(C.GrammarToolInputJsonBuffer):
  match result expected:
    case Done{C.GrammarToolInputJsonUpdate{+actual,delta}} Done{wanted}:
      do IO<C.GrammarToolInputJsonBuffer>:
        Assert.assertion(sameBuffer(actual,buffer) && sameDelta(delta,wanted), label)
        return actual
    case Fail{error} Fail{wanted}:
      do IO<C.GrammarToolInputJsonBuffer>:
        Assert.assertion(String.eq(C.errorMessage(error),wanted) && sameBuffer(previous,buffer), label)
        return previous
    case _ _: IO.die(C.GrammarToolInputJsonBuffer,1,"grammar transition outcome differs: " ++ label)

def transitions(steps: List<&2, Step>, +buffer: C.GrammarToolInputJsonBuffer, +label: String) -> IO(Unit):
  match steps:
    case Nil{}: IO.pure(Unit,Unit{})
    case Step{property,next,close,expected,wanted} <> rest:
      do IO<Unit>:
        updated : C.GrammarToolInputJsonBuffer <- checked(C.appendGrammarToolInputJsonDelta(buffer,property,next,close),buffer,expected,wanted,label)
        transitions(rest,updated,label)

def argumentResult(actual: Result<&2, &2, C.Error, String>, expected: Result<&2, &2, String, String>) -> Bool:
  match actual expected:
    case Done{a} Done{b}: U.equal(a,b)
    case Fail{a} Fail{b}: String.eq(C.errorMessage(a),b)
    case _ _: False{}

def argument(name: String, arguments: R.Record<V.Value>, property: String, expected: Result<&2, &2, String, String>, label: String) -> IO(Unit):
  Assert.assertion(argumentResult(C.getGrammarToolInput(name,arguments,property),expected),label)
