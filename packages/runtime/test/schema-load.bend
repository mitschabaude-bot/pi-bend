import Base
import ../src/schema.bend as L
import ../src/schema.bend as S
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ../src/big-nat.bend as B
import ./schema.bend as T

def loaded(result: L.Loaded()) -> IO(S.Schema):
  match result:
    case Done{schema}: IO.pure(S.Schema, schema)
    case Fail{L.LoadError{path, _}}: IO.die(S.Schema, 1, "unexpected schema load error: " ++ String.join(path, "/"))

def unsupported(result: L.Loaded(), expectedPath: String, expectedKey: String) -> IO(Unit):
  match result:
    case Fail{L.LoadError{path, L.UnsupportedKeyword{key}}}: T.assertion(String.eq(String.join(path, "/"), expectedPath) && String.eq(key, expectedKey), "unsupported schema path/keyword")
    case _: T.assertion(False{}, "unsupported schema must fail explicitly")

def invalid(result: L.Loaded(), expectedPath: String) -> IO(Unit):
  match result:
    case Fail{L.LoadError{path, L.InvalidSchema{_}}}: T.assertion(String.eq(String.join(path, "/"), expectedPath), "invalid schema path")
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

def exactCount(result: Result<&2, &2, L.LoadError, B.BigNat>, expected: String) -> IO(Unit):
  match result:
    case Done{value}: T.assertion(String.eq(B.toDecimal(value), expected), "count conversion must preserve the exact binary64 integer")
    case Fail{_}: T.assertion(False{}, "valid integer count rejected")

def referenceCycle(result: L.Loaded()) -> IO(Unit):
  match result:
    case Fail{L.LoadError{_, L.UnsupportedReferenceCycle{_}}}: IO.pure(Unit, Unit{})
    case _: T.assertion(False{}, "recursive references must remain explicit unsupported errors")

def externalReference(result: L.Loaded()) -> IO(Unit):
  match result:
    case Fail{L.LoadError{_, L.UnsupportedReference{_}}}: IO.pure(Unit, Unit{})
    case _: T.assertion(False{}, "external/anchor references must remain explicit unsupported errors")

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
    unresolved : S.Schema <- loaded(L.compile(object("$ref", V.Text{"#/$defs/x"})))
    T.assertion(Bool.not(S.check(unresolved, V.Null{})), "unresolved local references reject")
    unsupported(L.compile(object("pattern", V.Text{"x"})), "pattern", "pattern")
    unsupported(L.compile(object("anyOf", V.ArrayValue{V.Boolean{True{}} <> object("pattern", V.Text{"x"}) <> Nil{}})), "anyOf/1/pattern", "pattern")
    unsupported(L.compile(object("properties", object("x", object("format", V.Text{"email"})))), "properties/x/format", "format")
    invalid(L.compile(object("uniqueItems", V.Text{"true"})), "uniqueItems")
    invalid(L.compile(object("minItems", V.Number{F.negate(F.fromU32(1))})), "minItems")
    invalid(L.compile(object("maxItems", V.Number{F.divide(F.fromU32(1), F.fromU32(2))})), "maxItems")
    invalid(L.compile(object("minProperties", V.Text{"2"})), "minProperties")
    invalid(L.compile(object("maxProperties", V.Number{F.nan()})), "maxProperties")
    invalid(L.compile(object("minContains", V.Number{F.infinity(False{})})), "minContains")
    invalid(L.compile(V.ObjectValue{R.Record{R.Property{"contains", V.Boolean{True{}}} <> R.Property{"maxContains", V.Number{F.negate(F.fromU32(1))}} <> Nil{}}}), "maxContains")
    exactCount(L.readCount(V.Number{F.fromBits(0, 0)}, Nil{}), "0")
    exactCount(L.readCount(V.Number{F.fromBits(2147483648, 0)}, Nil{}), "0")
    exactCount(L.readCount(V.Number{F.fromBits(1072693248, 0)}, Nil{}), "1")
    exactCount(L.readCount(V.Number{F.fromBits(1106247680, 0)}, Nil{}), "4294967296")
    exactCount(L.readCount(V.Number{F.fromBits(1128267776, 0)}, Nil{}), "9007199254740992")
    exactCount(L.readCount(V.Number{F.fromBits(1420970413, 630506365)}, Nil{}), "10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104")
    exactCount(L.readCount(V.Number{F.fromBits(2146435071, 4294967295)}, Nil{}), "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368")
    ordinaryKey("x")
    ordinaryKey("__proto__")
    ordinaryKey("constructor")
    ordinaryKey("toString")
    ignored : S.Schema <- loaded(L.compile(object("default", object("pattern", V.Text{"not a schema"}))))
    T.assertion(S.check(ignored, V.Null{}), "annotation values are not interpreted as schemas")
    nativeKey : S.Schema <- loaded(L.compile(V.ObjectValue{R.Record{R.Property{"$ref", V.Text{"#/$defs/__proto__"}} <> R.Property{"$defs", object("__proto__", object("type", V.Text{"integer"}))} <> Nil{}}}))
    T.assertion(S.check(nativeKey, V.Number{F.fromU32(1)}), "reference pointers traverse ordinary native dictionary keys")
    referenceCycle(L.compile(object("$ref", V.Text{"#"})))
    referenceCycle(L.compile(V.ObjectValue{R.Record{R.Property{"$ref", V.Text{"#/$defs/a"}} <> R.Property{"$defs", object("a", object("$ref", V.Text{"#/%24defs/a"}))} <> Nil{}}}))
    externalReference(L.compile(object("$ref", V.Text{"other.json#/$defs/x"})))
    externalReference(L.compile(object("$ref", V.Text{"#anchor"})))
    invalid(L.compile(object("$ref", V.Null{})), "$ref")
    invalid(L.compile(object("$defs", V.Null{})), "$defs")
    IO.print("PASS native schema loading, malformed/unsupported paths, immutable inputs and ordinary dictionary keys")
