import Base
import ../src/providers/anthropic.models.bend as Catalog
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ./anthropic-sse-bodies.bend as Bodies
import ../../runtime/src/f64.bend as F

# pi-mono f07218c4d packages/ai/test/anthropic-cache-write-1h-cost.test.ts.
# claude-opus-4-8: input 5, cacheWrite (5m) 6.25 per Mtok; 1h write = 2x input = 10.
def plain() -> H.Options(): H.direct(H.streamOptions(None{}, None{}, None{}), None{}, None{})

def checked(usage: T.Usage, +cost: F64, +longWrite: F64, +name: String) -> IO(Unit):
  match usage:
    case T.Usage{_, _, _, write, long, _, _, T.UsageCost{_, _, _, writeCost, _}}:
      do IO<Unit>:
        H.equalNumber(write, F.fromU32(1000000), name ++ ": cacheWrite")
        H.equalNumber(Maybe.default(&2, F64, long, F.fromU32(0)), longWrite, name ++ ": cacheWrite1h")
        H.check(H.near(writeCost, cost, F.divide(F.fromU32(1), F.fromU32(2000000000))), name ++ ": cost.cacheWrite")

def priced(body: String, +cost: F64, +longWrite: F64, +name: String) -> IO(Unit):
  do IO<Unit>:
    outcome : H.Outcome <- H.run(Catalog.model_claude_opus_4_8(), H.context(H.user("hi", 1) <> Nil{}), plain(), H.Respond{body <> Nil{}})
    checked(H.usageOf(H.messageOf(outcome)), cost, longWrite, name)
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    # 600k * 6.25/Mtok + 400k * 10/Mtok = 3.75 + 4.0 = 7.75
    priced(Bodies.cache1h(), F.divide(F.fromU32(31), F.fromU32(4)), F.fromU32(400000), "prices the 1h portion at 2x input and the rest at the 5m rate")
    # 1M * 6.25/Mtok = 6.25
    priced(Bodies.cache5m(), F.divide(F.fromU32(25), F.fromU32(4)), F.fromU32(0), "falls back to the 5m rate when no breakdown is reported")
