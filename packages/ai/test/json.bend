import Base
import ../src/types.bend as T
import ../src/utils/json.bend as J
import ../../runtime/src/record.bend as R
import ../../runtime/src/ordered-map.bend as M
import ../../runtime/src/utf16.bend as U

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def check(actual: Maybe<&2, String>, expected: String) -> IO(Unit):
  match actual:
    case None{}: assertion(False{}, "numeric serializer invariant failed")
    case Some{value}: assertion(String.eq(value, expected), "JSON serialization changed")

def countValue(value: Maybe<&2, U32>, expected: U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{actual}: U32.is_eq(actual, expected)

def absent(value: Maybe<&2, U32>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}

def nested(count: Nat, value: T.JsonValue) -> T.JsonValue:
  match count:
    case 0n: value
    case 1n+n: nested(n, T.JsonArray{value <> Nil{}})

def repeat(count: Nat, +char: Char) -> String:
  match count:
    case 0n: ""
    case 1n+n: SCon{char, repeat(n, char)}

def main() -> IO(Unit):
  do IO<Unit>:
    +units : String = SCon{Chr{55357}, SCon{Chr{56832}, SNil{}}}
    +scalar : String = SCon{Chr{128512}, SNil{}}
    assertion(U.equal(units, scalar), "surrogate pair and scalar must compare equally")
    assertion(Bool.not(U.equal("é", "é")), "representation normalization must not normalize Unicode spelling")
    +record : R.Record<U32> = R.set(U32, R.set(U32, R.new(U32), units, 1), scalar, 2)
    assertion(countValue(R.get(U32, record, units), 1), "record lookup must use native string equality")
    assertion(countValue(R.get(U32, R.remove(U32, record, units), scalar), 2), "record delete must use native string equality")
    +map : M.OrderedMap<U32> = M.set(U32, M.set(U32, M.new(U32), scalar, 1), units, 2)
    assertion(countValue(M.get(U32, map, scalar), 1), "Map lookup must use native string equality")
    assertion(countValue(M.get(U32, M.remove(U32, map, scalar), units), 2), "Map delete must use native string equality")
    check(J.stringify(T.JsonArray{Nil{}}), "[]")
    check(J.stringify(T.JsonObject{R.new(T.JsonValue)}), "{}")
    check(J.stringify(nested(U32.to_nat(2000), T.JsonNull{})), repeat(U32.to_nat(2000), Chr{91}) ++ "null" ++ repeat(U32.to_nat(2000), Chr{93}))
    IO.print("PASS deep JSON nesting and native dictionary keys and Unicode quoting")
