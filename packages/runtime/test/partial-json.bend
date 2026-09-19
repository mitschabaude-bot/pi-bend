import Base
import ../src/partial-json.bend as P
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/f64.bend as F
import ../src/u64.bend as W
import ../src/utf16.bend as U
import ./schema.bend as A
import ../../ai/src/utils/json-parse.bend as Streaming

# Compare every numeric leaf bit-for-bit, including nested NaN, infinity and
# negative zero. Object order uses native structural dictionary semantics.
def matchedField(value: V.Value, other: Maybe<&2,V.Value>, rest: List<&2,V.Comparison>) -> Maybe<&2,List<&2,V.Comparison>>:
  match other:
    case None{}: None{}
    case Some{right}: Some{V.Values{value,right} <> rest}

@unsafe
def equal(work: Maybe<&2,List<&2,V.Comparison>>) -> Bool:
  match work:
    case None{}: False{}
    case Some{Nil{}}: True{}
    case Some{V.Values{V.Null{},V.Null{}} <> rest}: equal(Some{rest})
    case Some{V.Values{V.Boolean{+a},V.Boolean{+b}} <> rest}: ((a && b) || (Bool.not(a) && Bool.not(b))) && equal(Some{rest})
    case Some{V.Values{V.Number{a},V.Number{b}} <> rest}: W.equal(F.toBits(a),F.toBits(b)) && equal(Some{rest})
    case Some{V.Values{V.Text{a},V.Text{b}} <> rest}: U.equal(a,b) && equal(Some{rest})
    case Some{V.Values{V.ArrayValue{a},V.ArrayValue{b}} <> rest}: equal(Some{V.Arrays{a,b} <> rest})
    case Some{V.Values{V.ObjectValue{a},V.ObjectValue{b}} <> rest}: equal(Some{V.Fields{R.entries(V.Value,a),b} <> rest})
    case Some{V.Arrays{Nil{},Nil{}} <> rest}: equal(Some{rest})
    case Some{V.Arrays{a <> xs,b <> ys} <> rest}: equal(Some{V.Values{a,b} <> V.Arrays{xs,ys} <> rest})
    case Some{V.Fields{Nil{},R.Record{Nil{}}} <> rest}: equal(Some{rest})
    case Some{V.Fields{R.Property{+key,value} <> tail,+other} <> rest}: equal(matchedField(value,R.get(V.Value,other,key),V.Fields{tail,R.remove(V.Value,other,key)} <> rest))
    case _: False{}

def same(left: V.Value, right: V.Value) -> Bool:
  equal(Some{V.Values{left,right} <> Nil{}})

def rawMatches(actual: Result<&2,&2,P.Error,V.Value>, expected: Maybe<&2,V.Value>) -> Bool:
  match actual expected:
    case Done{a} Some{b}: same(a,b)
    case Fail{_} None{}: True{}
    case _ _: False{}

def raw(input: Maybe<&2,String>, expected: Maybe<&2,V.Value>) -> Bool:
  match input:
    case None{}: True{}
    case Some{text}: rawMatches(P.parse(text),expected)

def check(+input: Maybe<&2,String>, partial: Maybe<&2,V.Value>, streaming: V.Value, +label: String) -> IO(Unit):
  do IO<Unit>:
    A.assertion(raw(input,partial),"partial dependency: " ++ label)
    A.assertion(same(Streaming.parseStreamingJson(input),streaming),"streaming parse: " ++ label)

def opens(count: Nat, result: String) -> String:
  match count:
    case 0n: result
    case 1n+n: opens(n,"[" ++ result)

def nested(count: Nat, value: V.Value) -> V.Value:
  match count:
    case 0n: value
    case 1n+n: nested(n,V.ArrayValue{value <> Nil{}})

def deep() -> IO(Unit):
  +expected = nested(2000n,V.Number{F.fromU32(1)})
  check(Some{opens(2000n,"1")},Some{expected},expected,"2000 unclosed containers")


# Literal JSON keys remain data even when a host object would treat them as
# prototype setters. This is part of the approved native-value representation.
def literalKeys() -> IO(Unit):
  +fields = {R.Record{R.Property{"__proto__",V.ObjectValue{R.Record{R.Property{"x",V.Number{F.fromU32(1)}} <> Nil{}}}} <> R.Property{"constructor",V.Number{F.fromU32(2)}} <> Nil{}} : R.Record<V.Value>}
  check(Some{"{\"__proto__\":{\"x\":1},\"constructor\":2"},Some{V.ObjectValue{fields}},V.ObjectValue{fields},"literal dictionary keys during partial recovery")
