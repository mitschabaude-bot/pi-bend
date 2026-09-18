import Base
import ../src/schema-load.bend as L
import ../src/schema.bend as S
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ./schema.bend as T

def loaded(result: L.Loaded()) -> IO(S.Schema):
  match result:
    case Done{schema}: IO.pure(S.Schema, schema)
    case Fail{L.Error{path, _}}: IO.die(S.Schema, 1, "unexpected schema load error: " ++ String.join(path, "/"))

def unsupported(result: L.Loaded(), expectedPath: String, expectedKey: String) -> IO(Unit):
  match result:
    case Fail{L.Error{path, L.UnsupportedKeyword{key}}}: T.assertion(String.eq(String.join(path, "/"), expectedPath) && String.eq(key, expectedKey), "unsupported schema path/keyword")
    case _: T.assertion(False{}, "unsupported schema must fail explicitly")

def invalid(result: L.Loaded(), expectedPath: String) -> IO(Unit):
  match result:
    case Fail{L.Error{path, L.InvalidSchema{_}}}: T.assertion(String.eq(String.join(path, "/"), expectedPath), "invalid schema path")
    case _: T.assertion(False{}, "malformed schema must not become accepting")

def object(key: String, value: V.Value) -> V.Value:
  V.ObjectValue{R.Record{R.Property{key, value} <> Nil{}}}

def ordinaryKey(+key: String) -> IO(Unit):
  do IO<Unit>:
    +declaration : V.Value = V.ObjectValue{R.Record{R.Property{"additionalProperties", V.Boolean{False{}}} <> R.Property{"required", V.ArrayValue{V.Text{key} <> Nil{}}} <> R.Property{"properties", object(key, object("type", V.Text{"integer"}))} <> Nil{}}}
    +schema : S.Schema <- loaded(L.compile(declaration))
    T.assertion(S.check(schema, object(key, V.Number{F.fromU32(1)})), "loaded property with ordinary string key")
    T.assertion(Bool.not(S.check(schema, V.ObjectValue{R.new(V.Value)})), "required field cannot be inherited")
    T.assertion(Bool.not(S.check(schema, object(key, V.Null{}))), "declared property must retain its schema")
    T.assertion(Bool.not(S.check(schema, object("extra", V.Number{F.fromU32(1)}))), "additionalProperties applies independently of keyword order")
    T.assertion(V.equal(declaration, V.ObjectValue{R.Record{R.Property{"additionalProperties", V.Boolean{False{}}} <> R.Property{"required", V.ArrayValue{V.Text{key} <> Nil{}}} <> R.Property{"properties", object(key, object("type", V.Text{"integer"}))} <> Nil{}}}), "schema loading preserves input")

def main() -> IO(Unit):
  do IO<Unit>:
    +accept : S.Schema <- loaded(L.compile(V.Boolean{True{}}))
    reject : S.Schema <- loaded(L.compile(V.Boolean{False{}}))
    T.assertion(S.check(accept, V.Null{}) && Bool.not(S.check(reject, V.Null{})), "boolean schemas")
    invalid(L.compile(V.Null{}), "")
    invalid(L.compile(V.Text{"number"}), "")
    invalid(L.compile(object("type", V.Text{"unknown"})), "type")
    invalid(L.compile(object("type", V.ArrayValue{V.ArrayValue{V.Text{"number"} <> Nil{}} <> Nil{}})), "type")
    invalid(L.compile(object("properties", V.Boolean{True{}})), "properties")
    invalid(L.compile(object("required", V.ArrayValue{V.Null{} <> Nil{}})), "required")
    invalid(L.compile(object("enum", V.Text{"x"})), "enum")
    invalid(L.compile(object("allOf", V.Boolean{True{}})), "allOf")
    invalid(L.compile(object("not", V.Null{})), "not")
    invalid(L.compile(object("items", V.ArrayValue{V.Boolean{True{}} <> V.Null{} <> Nil{}})), "items/1")
    invalid(L.compile(object("properties", object("x", object("minimum", V.Text{"1"})))), "properties/x/minimum")
    invalid(L.compile(object("maximum", V.Number{F.infinity(False{})})), "maximum")
    unsupported(L.compile(object("$ref", V.Text{"#/$defs/x"})), "$ref", "$ref")
    unsupported(L.compile(object("minLength", V.Number{F.fromU32(1)})), "minLength", "minLength")
    unsupported(L.compile(object("anyOf", V.ArrayValue{V.Boolean{True{}} <> object("pattern", V.Text{"x"}) <> Nil{}})), "anyOf/1/pattern", "pattern")
    unsupported(L.compile(object("properties", object("x", object("format", V.Text{"email"})))), "properties/x/format", "format")
    ordinaryKey("x")
    ordinaryKey("__proto__")
    ordinaryKey("constructor")
    ordinaryKey("toString")
    ignored : S.Schema <- loaded(L.compile(object("default", object("pattern", V.Text{"not a schema"}))))
    T.assertion(S.check(ignored, V.Null{}), "annotation values are not interpreted as schemas")
    IO.print("PASS native schema loading, malformed/unsupported paths, immutable inputs and ordinary dictionary keys")
