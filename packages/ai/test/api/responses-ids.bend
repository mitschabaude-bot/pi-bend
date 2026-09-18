import Base
import ../../src/api/openai-responses-ids.bend as I
import ../../src/api/transform-messages.bend as Transform
import ../../src/types.bend as T
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as A

def source(foreignProvider: Bool, foreignApi: Bool) -> T.AssistantMessage<Unit,Unit>:
  +zero = F.fromU32(0)
  T.AssistantMessage{Nil{},Bool.pick(String,foreignApi,"other","openai-responses"),Bool.pick(String,foreignProvider,"other","openai"),"source",None{},None{},None{},None{},T.Usage{zero,zero,zero,zero,None{},None{},zero,T.UsageCost{zero,zero,zero,zero,zero}},T.Stop{},None{},None{},None{},None{},zero}

def check(id: String, allowed: Bool, foreignProvider: Bool, foreignApi: Bool, expected: String, label: String) -> IO(Unit):
  providers = Bool.pick(List<&2,String>,allowed,"openai" <> Nil{},"other" <> Nil{})
  A.assertion(String.eq(I.normalizeToolCallId(Unit,Unit,id,Transform.Target{"openai-responses","openai","target"},source(foreignProvider,foreignApi),providers),expected),label)
