import Base
import ./plain-validation.bend as T
import ./validation-errors.bend as E
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema.bend as Schema
import ../../runtime/src/schema-load.bend as Loader
import ../../runtime/test/schema-load.bend as L
import ../../runtime/test/schema.bend as Assert

def object(key: String, value: V.Value) -> V.Value:
  V.ObjectValue{R.Record{R.Property{key, value} <> Nil{}}}

def wrapped(schema: V.Value) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", object("value", schema)} <> R.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}

def rejected(+kind: String, +input: String) -> IO(Unit):
  E.validated("echo", wrapped(object("type", V.Text{kind})), object("value", V.Text{input}), "Validation failed for tool \"echo\":\n  - value: must be " ++ kind ++ "\n\nReceived arguments:\n{\n  \"value\": \"" ++ input ++ "\"\n}")

def main() -> IO(Unit):
  do IO<Unit>:
    +arms : V.Value = V.ArrayValue{object("type", V.Text{"number"}) <> object("type", V.Text{"null"}) <> Nil{}}
    +nullArgument : V.Value = object("value", V.Null{})
    T.check(nullArgument, wrapped(object("oneOf", arms)), nullArgument, nullArgument, "preserves a value that already matches a oneOf nullable union arm")
    +input : V.Value = object("value", V.Text{"42"})
    T.check(input, wrapped(object("anyOf", arms)), object("value", V.Number{F.fromU32(42)}), input, "still coerces nullable unions when the original value does not match any arm")
    +arraySchema : V.Value = wrapped(V.ObjectValue{R.Record{R.Property{"type", V.ArrayValue{V.Text{"array"} <> V.Text{"null"} <> Nil{}}} <> R.Property{"items", object("type", V.Text{"string"})} <> Nil{}}})
    validator : Schema.Schema <- L.loaded(Loader.compile(arraySchema))
    # Upstream exercises a generated JS validator separately. The native
    # equivalent checks the compiled schema directly before the public path.
    Assert.assertion(Schema.check(validator, nullArgument), "accepts null for nullable array schemas with items: compiled checker")
    T.check(nullArgument, arraySchema, nullArgument, nullArgument, "accepts null for nullable array schemas with items")
    # Original named case: rejects invalid coercions for serialized plain JSON schemas.
    rejected("boolean", "1")
    rejected("boolean", "0")
    rejected("null", "null")
    rejected("integer", "42.1")
    IO.print("PASS four original validation cases: nullable oneOf, union coercion, nullable array and invalid coercions (8 assertions)")
