import Base
import ../src/schema.bend as S
import ../src/schema.bend as E
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ../src/big-nat.bend as B
import ./schema.bend as T
import ../src/schema.bend as Loader
import ./schema-load.bend as L

def empty(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case Nil{}: True{}
    case _: False{}

def missingAndNull(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.MissingFields{a <> Nil{}}} <> E.Issue{b <> Nil{}, E.ExpectedType{S.IntegerType{}}} <> Nil{}: String.eq(a, "absent") && String.eq(b, "present")
    case _: False{}

def nested(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{a <> b <> c <> Nil{}, E.ExpectedType{S.NumberType{}}} <> Nil{}: String.eq(a, "a/b") && String.eq(b, "0") && String.eq(c, "")
    case _: False{}

def extras(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{+a <> Nil{}, E.Rejected{}} <> E.Issue{+b <> Nil{}, E.Rejected{}} <> E.Issue{Nil{}, E.AdditionalFields{c <> d <> Nil{}}} <> Nil{}: String.eq(a, "10") && String.eq(b, "2") && String.eq(a, c) && String.eq(b, d)
    case _: False{}

def unionFailure(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.ExpectedType{S.StringType{}}} <> E.Issue{Nil{}, E.ExpectedType{S.IntegerType{}}} <> E.Issue{Nil{}, E.NoAlternative{}} <> Nil{}: True{}
    case _: False{}

def exclusiveFailure(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.ExclusiveAlternatives{matched}} <> Nil{}: B.equal(matched, B.fromU32(2))
    case _: False{}

def containsFailure(issues: List<&2, E.Issue>, expected: B.BigNat) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.ContainsCount{actual, S.CountBounds{minimum, None{}}}} <> Nil{}: B.equal(actual, B.one()) && B.equal(minimum, expected)
    case _: False{}

def numberBounds(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.NumericMinimum{lo, True{}}} <> E.Issue{Nil{}, E.NumericMaximum{hi, False{}}} <> Nil{}: V.equal(V.Number{lo}, V.Number{F.fromU32(2)}) && V.equal(V.Number{hi}, V.Number{F.fromU32(1)})
    case _: False{}

def loadedTypes(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.ExpectedTypes{S.IntegerType{} <> S.StringType{} <> Nil{}}} <> Nil{}: True{}
    case _: False{}

def loadedPropertyOrder(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{a <> Nil{}, E.ExpectedType{S.IntegerType{}}} <> E.Issue{b <> Nil{}, E.ExpectedType{S.IntegerType{}}} <> Nil{}: String.eq(a, "10") && String.eq(b, "2")
    case _: False{}

def loadedKeywordOrder(issues: List<&2, E.Issue>) -> Bool:
  match issues:
    case E.Issue{Nil{}, E.NumericMaximum{_, True{}}} <> E.Issue{Nil{}, E.NumericMinimum{_, True{}}} <> Nil{}: True{}
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +integer : S.Schema = S.JsonKind{S.IntegerType{}}
    +string : S.Schema = S.JsonKind{S.StringType{}}
    +properties : R.Record<S.Schema> = R.Record{R.Property{"present", integer} <> Nil{}}
    T.assertion(missingAndNull(E.errors(S.Object{properties, "absent" <> "present" <> Nil{}, S.Accept{}}, V.ObjectValue{R.Record{R.Property{"present", V.Null{}} <> Nil{}}})), "missing fields stay distinct from present null")
    +inner : S.Schema = S.Object{R.Record{R.Property{"", S.JsonKind{S.NumberType{}}} <> Nil{}}, Nil{}, S.Accept{}}
    +outer : S.Schema = S.Object{R.Record{R.Property{"a/b", S.Array{Nil{}, inner}} <> Nil{}}, Nil{}, S.Accept{}}
    +value : V.Value = V.ObjectValue{R.Record{R.Property{"a/b", V.ArrayValue{V.ObjectValue{R.Record{R.Property{"", V.Text{"bad"}} <> Nil{}}} <> Nil{}}} <> Nil{}}}
    T.assertion(nested(E.errors(outer, value)), "paths retain slash-containing and empty fields with array indices")
    T.assertion(extras(E.errors(S.Object{R.new(S.Schema), Nil{}, S.Reject{}}, V.ObjectValue{R.Record{R.Property{"10", V.Null{}} <> R.Property{"2", V.Null{}} <> Nil{}}})), "additional issues preserve native dictionary order")
    T.assertion(unionFailure(E.errors(S.Any{string <> integer <> Nil{}}, V.Null{})), "failed alternatives retain child reasons before parent")
    T.assertion(empty(E.errors(S.Any{string <> integer <> Nil{}}, V.Number{F.fromU32(1)})), "successful union suppresses failed alternatives")
    T.assertion(exclusiveFailure(E.errors(S.One{integer <> S.JsonKind{S.NumberType{}} <> string <> Nil{}}, V.Number{F.fromU32(1)})), "ambiguous oneOf reports match count without unrelated failures")
    T.assertion(empty(E.errors(S.One{string <> integer <> Nil{}}, V.Number{F.fromU32(1)})), "exactly one success suppresses failed alternatives")
    T.assertion(empty(E.errors(S.Not{integer}, V.Null{})), "negation does not leak child errors")
    +huge : B.BigNat = B.shiftLeft(B.one(), 100n)
    T.assertion(containsFailure(E.errors(S.Contains{integer, S.CountBounds{huge, None{}}}, V.ArrayValue{V.Number{F.fromU32(1)} <> V.Null{} <> Nil{}}), huge), "contains reports exact compact counts without leaking child errors")
    T.assertion(numberBounds(E.errors(S.All{S.Minimum{F.fromU32(2), True{}} <> S.Maximum{F.fromU32(1), False{}} <> Nil{}}, V.Number{F.fromU32(1)})), "all violated numeric bounds are retained")
    T.assertion(empty(E.errors(S.Array{Nil{}, integer}, V.Null{})), "array keyword ignores non-arrays")
    T.assertion(empty(E.errors(S.Object{properties, "present" <> Nil{}, S.Reject{}}, V.Null{})), "object keyword ignores non-objects")
    +union : S.Schema <- L.loaded(Loader.compile(L.object("type", V.ArrayValue{V.Text{"integer"} <> V.Text{"string"} <> Nil{}})))
    T.assertion(loadedTypes(E.errors(union, V.Null{})), "type arrays retain one aggregate type diagnostic")
    T.assertion(empty(E.errors(union, V.Text{"ok"})), "type array still accepts matching members")
    +typeDecl : V.Value = L.object("type", V.Text{"integer"})
    +ordered : S.Schema <- L.loaded(Loader.compile(L.object("properties", V.ObjectValue{R.Record{R.Property{"10", typeDecl} <> R.Property{"2", typeDecl} <> Nil{}}})))
    T.assertion(loadedPropertyOrder(E.errors(ordered, V.ObjectValue{R.Record{R.Property{"2", V.Null{}} <> R.Property{"10", V.Null{}} <> Nil{}}})), "property diagnostics retain schema declaration order, including numeric-looking keys")
    +bounds : S.Schema <- L.loaded(Loader.compile(V.ObjectValue{R.Record{R.Property{"minimum", V.Number{F.fromU32(2)}} <> R.Property{"maximum", V.Number{F.fromU32(0)}} <> Nil{}}}))
    T.assertion(loadedKeywordOrder(E.errors(bounds, V.Number{F.fromU32(1)})), "diagnostic keyword order is independent of declaration order")
    T.assertion(empty(E.errorsLimited(S.Reject{}, V.Null{}, 0n)), "zero diagnostic budget emits nothing")
    T.assertion(exclusiveFailure(E.errorsLimited(S.One{integer <> S.JsonKind{S.NumberType{}} <> Nil{}}, V.Number{F.fromU32(1)}, 1n)), "limited collection retains complete issue metadata")
    IO.print("PASS native structured schema diagnostics, paths, union isolation and exact counts")
