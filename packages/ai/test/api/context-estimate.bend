import Base
import ../../src/types.bend as T
import ../../src/utils/estimate.bend as E
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as Assert
import ./thinking-options.bend as NumberTest

def sameIndex(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: Nat.is_eq(a, b)
    case _ _: False{}

def same(actual: E.ContextUsageEstimate, expected: E.ContextUsageEstimate) -> Bool:
  match actual expected:
    case E.ContextUsageEstimate{a, b, c, d} E.ContextUsageEstimate{e, f, g, h}: NumberTest.numberEqual(a, e) && NumberTest.numberEqual(b, f) && NumberTest.numberEqual(c, g) && sameIndex(d, h)

def individuals(messages: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>, expected: List<&2, F64>) -> Bool:
  match messages expected:
    case Nil{} Nil{}: True{}
    case head <> tail value <> rest: NumberTest.numberEqual(E.estimateMessageTokens(~Unit, ~Unit, head), value) && individuals(tail, rest)
    case _ _: False{}

def check(+messages: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>, expected: E.ContextUsageEstimate, individual: List<&2, F64>, label: String) -> IO(Unit):
  Assert.assertion(same(E.estimateContextTokens(~Unit, ~Unit, T.TranscriptContext{messages}), expected) && individuals(messages, individual), label)

def repeat(count: Nat, +char: Char) -> String:
  match count:
    case 0n: ""
    case 1n+n: SCon{char, repeat(n, char)}
