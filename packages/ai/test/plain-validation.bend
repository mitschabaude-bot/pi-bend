import Base
import ../../runtime/src/utf16.bend as U
import ../src/utils/validation.bend as Validation
import ../src/types.bend as Ai
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/test/schema.bend as T

def outcome(result: Validation.ToolValidation(), expected: V.Value, label: String) -> IO(Unit):
  match result:
    case Done{actual}: T.assertion(V.equal(actual, expected), label)
    case Fail{_}: T.assertion(False{}, "unexpected plain validation failure: " ++ label)

def failure(result: Validation.ToolValidation(), received: V.Value, label: String) -> IO(Unit):
  match result:
    case Fail{Validation.InvalidToolArguments{name, _, original, _, _}}: T.assertion(String.eq(name, "echo") && V.equal(original, received), label)
    case _: T.assertion(False{}, "expected structured argument rejection: " ++ label)

def check(+input: V.Value, schema: V.Value, expected: V.Value, original: V.Value, label: String) -> IO(Unit):
  do IO<Unit>:
    outcome(Validation.validatePlainToolArguments(Ai.Tool{"echo", "", schema, None{}}, Ai.ToolCall{"id", "echo", input, None{}, None{}}), expected, label)
    T.assertion(V.equal(input, original), "plain validation must preserve original arguments")

def messageMatches(message: Maybe<&2, String>, expected: String, label: String) -> IO(Unit):
  match message:
    case Some{actual}: T.assertion(U.equal(actual, expected), "complete validation failure: " ++ label)
    case None{}: T.assertion(False{}, "missing argument error rendering: " ++ label)

def failureMessage(result: Validation.ToolValidation(), expected: String, label: String) -> IO(Unit):
  match result:
    case Fail{error}: messageMatches(Validation.formatToolValidationError(error), expected, label)
    case Done{_}: T.assertion(False{}, "expected argument failure: " ++ label)

def reject(+input: V.Value, schema: V.Value, original: V.Value, message: String, +label: String) -> IO(Unit):
  do IO<Unit>:
    +result : Validation.ToolValidation() = Validation.validatePlainToolArguments(Ai.Tool{"echo", "", schema, None{}}, Ai.ToolCall{"id", "echo", input, None{}, None{}})
    failure(result, original, label)
    failureMessage(result, message, label)


def missing(result: Validation.ToolValidation()) -> IO(Unit):
  match result:
    case Fail{Validation.ToolNotFound{name}}: T.assertion(String.eq(name, "absent"), "missing tool name")
    case _: T.assertion(False{}, "missing tool must fail lookup")

def schemaFailure(result: Validation.ToolValidation()) -> IO(Unit):
  match result:
    case Fail{Validation.InvalidToolSchema{name, _}}: T.assertion(String.eq(name, "echo"), "invalid schema tool name")
    case _: T.assertion(False{}, "unsupported full schema must not validate arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    +input : V.Value = V.ObjectValue{R.Record{R.Property{"x", V.Number{F.fromU32(1)}} <> Nil{}}}
    +call : Ai.ToolCall<V.Value> = Ai.ToolCall{"id", "echo", input, None{}, None{}}
    missing(Validation.validatePlainToolCall(Nil{}, Ai.ToolCall{"id", "absent", input, None{}, None{}}))
    outcome(Validation.validatePlainToolCall(Ai.Tool{"echo", "", V.Boolean{True{}}, None{}} <> Ai.Tool{"echo", "", V.Boolean{False{}}, None{}} <> Nil{}, call), input, "first matching declaration wins")
    failure(Validation.validatePlainToolCall(Ai.Tool{"echo", "", V.Boolean{False{}}, None{}} <> Ai.Tool{"echo", "", V.Boolean{True{}}, None{}} <> Nil{}, call), input, "first rejecting declaration must not fall through")
    schemaFailure(Validation.validatePlainToolArguments(Ai.Tool{"echo", "", V.ObjectValue{R.Record{R.Property{"pattern", V.Text{"x"}} <> Nil{}}}, None{}}, call))
    IO.print("PASS plain validation lookup, first-match selection and unsupported schema failures")
