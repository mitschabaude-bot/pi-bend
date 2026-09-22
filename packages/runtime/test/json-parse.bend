import Base
import ../src/json.bend as P
import ../src/schema-value.bend as V
import ../src/f64.bend as F
import ../src/u64.bend as W
import ./schema.bend as A

def numberBits(left: V.Value, right: V.Value) -> Bool:
  match left right:
    case V.Number{a} V.Number{b}: W.equal(F.toBits(a),F.toBits(b))
    case _ _: True{}

def outcome(actual: Result<&2,&2,P.ParseError,V.Value>, expected: Maybe<&2,V.Value>) -> Bool:
  match actual expected:
    case Done{+a} Some{+b}: V.equal(a,b) && numberBits(a,b)
    case Fail{_} None{}: True{}
    case _ _: False{}

def check(text: String, expected: Maybe<&2,V.Value>, label: String) -> IO(Unit):
  A.assertion(outcome(P.parse(text),expected),label)

def repeat(count: Nat, +text: String, result: String) -> String:
  match count:
    case 0n: result
    case 1n+n: repeat(n,text,text ++ result)

def nested(count: Nat, result: V.Value) -> V.Value:
  match count:
    case 0n: result
    case 1n+n: nested(n,V.ArrayValue{result <> Nil{}})

def deep() -> IO(Unit):
  check(repeat(2000n,"[","0") ++ repeat(2000n,"]",""),Some{nested(2000n,V.Number{F.fromU32(0)})},"2000-level nested JSON without a depth cutoff")
