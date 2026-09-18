import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ../src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as S

def sameError(actual: D.DeclarationError, expected: D.DeclarationError) -> Bool:
  match actual expected:
    case D.NumberEncodingFailure{} D.NumberEncodingFailure{}: True{}

def sameText(actual: D.DeclarationResult<String>, expected: D.DeclarationResult<String>) -> Bool:
  match actual expected:
    case D.Success{a} D.Success{b}: String.eq(a, b)
    case D.Failure{a} D.Failure{b}: sameError(a, b)
    case _ _: False{}

def sameBool(actual: D.DeclarationResult<Bool>, expected: D.DeclarationResult<Bool>) -> Bool:
  match actual expected:
    case D.Success{a} D.Success{b}: Bool.not(Bool.xor(a, b))
    case D.Failure{a} D.Failure{b}: sameError(a, b)
    case _ _: False{}

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def check(+left: T.Tool<S.Value>, +right: T.Tool<S.Value>, expectedLeft: D.DeclarationResult<String>, expectedRight: D.DeclarationResult<String>, expectedEqual: D.DeclarationResult<Bool>, +label: String) -> IO(Unit):
  do IO<Unit>:
    assertion(sameText(D.serializeDeclaration(Transcript.toToolDeclaration(left)), expectedLeft), label ++ " left declaration")
    assertion(sameText(D.serializeDeclaration(Transcript.toToolDeclaration(right)), expectedRight), label ++ " right declaration")
    assertion(sameBool(Transcript.declarationsEqual(left, right), expectedEqual), label ++ " comparison")
