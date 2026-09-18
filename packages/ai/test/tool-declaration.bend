import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ../src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as S

def sameError(actual: D.DeclarationError, expected: D.DeclarationError) -> Bool:
  match actual expected:
    case D.OmittedSchema{} D.OmittedSchema{}: True{}
    case D.BigIntSchema{} D.BigIntSchema{}: True{}
    case D.UnsupportedSchemaHook{} D.UnsupportedSchemaHook{}: True{}
    case _ _: False{}

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

def check(+left: T.Tool<S.Value<U32>>, +right: T.Tool<S.Value<U32>>, expectedLeft: D.DeclarationResult<String>, expectedRight: D.DeclarationResult<String>, expectedEqual: D.DeclarationResult<Bool>, +label: String) -> IO(Unit):
  do IO<Unit>:
    assertion(sameText(D.serializeDeclaration(U32, Transcript.toToolDeclaration(U32, left)), expectedLeft), label ++ " left declaration")
    assertion(sameText(D.serializeDeclaration(U32, Transcript.toToolDeclaration(U32, right)), expectedRight), label ++ " right declaration")
    assertion(sameBool(Transcript.declarationsEqual(U32, left, right), expectedEqual), label ++ " comparison")
