import Base
import ../src/utils/validation.bend as Validation
import ../src/types.bend as Ai
import ../src/utils/validation-errors.bend as Errors
import ../src/utils/json.bend as Json
import ../src/utils/schema-json.bend as SchemaJson
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/utf16.bend as U
import ../../runtime/test/schema.bend as T

def rendered(result: Maybe<&2, String>, expected: String, label: String) -> IO(Unit):
  match result:
    case Some{actual}: T.assertion(U.equal(actual, expected), label)
    case None{}: T.assertion(False{}, "diagnostic JSON number formatting failed")

def message(name: String, input: V.Value, issues: List<&2, Errors.Issue>, expected: String) -> IO(Unit):
  rendered(Errors.formatValidationFailure(name, input, issues), expected, "upstream validation error text")

def path(location: Errors.Location, expected: String) -> IO(Unit):
  T.assertion(U.equal(Errors.formatValidationPath(location), expected), "upstream validation field path")

def pretty(input: V.Value, expected: String) -> IO(Unit):
  rendered(Json.stringifyPretty(SchemaJson.toJson(input)), expected, "indented original argument JSON")

def rejected(result: Validation.ToolValidation(), expected: String) -> IO(Unit):
  match result:
    case Fail{error}: rendered(Validation.formatToolValidationError(error), expected, "complete native validation error text")
    case Done{_}: T.assertion(False{}, "invalid fixture unexpectedly accepted")

def validated(+name: String, schema: V.Value, input: V.Value, expected: String) -> IO(Unit):
  rejected(Validation.validatePlainToolArguments(Ai.Tool{name, "", schema, None{}}, Ai.ToolCall{"id", name, input, None{}, None{}}), expected)

def main() -> IO(Unit):
  do IO<Unit>:
    message("echo", V.Null{}, Nil{}, "Validation failed for tool \"echo\":\nUnknown validation error\n\nReceived arguments:\nnull")
    T.assertion(String.eq(Errors.formatToolNotFound("missing"), "Tool \"missing\" not found"), "missing-tool diagnostic")
    # Numeric-looking keys retain native dictionary insertion order. This is
    # an approved representation difference, not JS enumeration emulation.
    pretty(V.ObjectValue{R.Record{R.Property{"10", V.Null{}} <> R.Property{"2", V.Boolean{True{}}} <> Nil{}}}, "{\n  \"10\": null,\n  \"2\": true\n}")
    IO.print("PASS empty issue fallback, missing-tool text and native dictionary order")
