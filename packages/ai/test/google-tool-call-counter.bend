import Base
import ../src/types.bend as T
import ../src/providers/google.models.bend as Catalog
import ./google-harness.bend as H
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/schema-value.bend as V

# Generated Gemini tool-call ids are `${name}_${Date.now()}_${++toolCallCounter}`
# with one module-level counter in upstream google-generative-ai.ts, so a
# second stream in the same process continues the sequence. Native check
# (no upstream test): two streams sharing the process counter.
def body() -> String:
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"lookup\",\"args\":{}}},{\"functionCall\":{\"name\":\"other\",\"args\":{}}}]},\"finishReason\":\"STOP\"}]}\n\n"

def lastPart(parts: List<&2, String>) -> String: Maybe.default(&2, String, List.head(&2, String, List.reverse(&2, String, parts)), "")

def suffixes(blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case T.AssistantToolCall{T.ToolCall{id, _, _, _, _}} <> rest: lastPart(String.split(id, '_')) <> suffixes(rest)
    case _ <> rest: suffixes(rest)

def shown(message: H.Message()) -> String: String.join(suffixes(T.assistantContent(V.Value, Unit, message)), ",")

def run() -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    first : H.Message() <- H.respondShared(Catalog.model_gemini_2_5_flash(), body() <> Nil{}, counter)
    second : H.Message() <- H.respondShared(Catalog.model_gemini_2_5_flash(), body() <> Nil{}, counter)
    +ids : String <- IO.pure(String, shown(first) ++ "|" ++ shown(second))
    Bool.pick(IO(Unit), String.eq(ids, "1,2|3,4"), IO.print("PASS native: generated Gemini tool call ids continue the process counter across streams"), IO.die(Unit, 1, "FAIL native: tool call id counters " ++ ids))

def main() -> IO(Unit): run()
