import Base
import ./primitive-coercion.bend as C
import ../src/utils/tool-declaration.bend as D
import ../src/utils/schema-json.bend as J
import ../src/utils/json.bend as Json
import ../src/types.bend as T
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def expectedDeclaration(result: D.DeclarationResult<Bool>, expected: Bool) -> IO(Unit):
  match result:
    case D.Success{value}: assertion(Bool.not(Bool.xor(value, expected)), "declaration equality")
    case D.Failure{_}: assertion(False{}, "unexpected declaration failure")

def encoded(value: Maybe<&2, String>, expected: String) -> IO(Unit):
  match value:
    case Some{actual}: assertion(String.eq(actual, expected), "schema wire encoding")
    case None{}: assertion(False{}, "schema wire encoding failed")

def main() -> IO(Unit):
  do IO<Unit>:
    # Cases from validation.test.ts: AJV-compatible primitive coercion.
    C.check(V.Text{"42"}, "number", V.Number{F.fromU32(42)}, "numeric string")
    C.check(V.Boolean{True{}}, "number", V.Number{F.fromU32(1)}, "boolean to number")
    C.check(V.Null{}, "number", V.Number{F.fromU32(0)}, "null to number")
    C.check(V.Text{"42"}, "integer", V.Number{F.fromU32(42)}, "integer string")
    C.check(V.Text{"true"}, "boolean", V.Boolean{True{}}, "true string")
    C.check(V.Text{"false"}, "boolean", V.Boolean{False{}}, "false string")
    C.check(V.Number{F.fromU32(1)}, "boolean", V.Boolean{True{}}, "one to boolean")
    C.check(V.Number{F.fromU32(0)}, "boolean", V.Boolean{False{}}, "zero to boolean")
    C.check(V.Null{}, "string", V.Text{""}, "null to string")
    C.check(V.Boolean{True{}}, "string", V.Text{"true"}, "boolean to string")
    C.check(V.Text{""}, "null", V.Null{}, "empty string to null")
    C.check(V.Number{F.fromU32(0)}, "null", V.Null{}, "zero to null")
    C.check(V.Boolean{False{}}, "null", V.Null{}, "false to null")
    C.checkTypes(V.Text{"1"}, "number" <> "string" <> Nil{}, V.Text{"1"}, "preserve matching union arm")
    C.checkTypes(V.Text{"1"}, "boolean" <> "number" <> Nil{}, V.Number{F.fromU32(1)}, "try alternative coercion")
    # Invalid conversions remain unchanged for the validator to reject.
    C.check(V.Text{"1"}, "boolean", V.Text{"1"}, "reject boolean one string")
    C.check(V.Text{"0"}, "boolean", V.Text{"0"}, "reject boolean zero string")
    C.check(V.Text{"null"}, "null", V.Text{"null"}, "reject null string")
    C.check(V.Text{"42.1"}, "integer", V.Text{"42.1"}, "reject fractional integer")
    +first : R.Record<V.Value> = R.set(V.Value, R.set(V.Value, R.new(V.Value), "10", V.Text{"ten"}), "2", V.Text{"two"})
    +second : R.Record<V.Value> = R.set(V.Value, R.set(V.Value, R.new(V.Value), "2", V.Text{"two"}), "10", V.Text{"ten"})
    assertion(V.equal(V.ObjectValue{first}, V.ObjectValue{second}), "object order must not affect equality")
    assertion(Bool.not(V.equal(V.ObjectValue{first}, V.ObjectValue{R.remove(V.Value, second, "2")})), "missing field changes equality")
    assertion(Bool.not(V.equal(V.ArrayValue{V.Text{"a"} <> V.Text{"b"} <> Nil{}}, V.ArrayValue{V.Text{"b"} <> V.Text{"a"} <> Nil{}})), "array order matters")
    encoded(Json.stringify(J.toJson(V.ObjectValue{first})), "{\"10\":\"ten\",\"2\":\"two\"}")
    expectedDeclaration(D.declarationsEqual(T.Tool{"a", "tool", V.ObjectValue{first}, None{}}, T.Tool{"a", "tool", V.ObjectValue{second}, None{}}), True{})
    expectedDeclaration(D.declarationsEqual(T.Tool{"a", "tool", V.ObjectValue{first}, None{}}, T.Tool{"a", "changed", V.ObjectValue{second}, None{}}), False{})
    IO.print("PASS native schemas, structural declaration equality, and 19 upstream primitive coercion cases")
