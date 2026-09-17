import Base
import ./json.bend as J
import ./util.bend as U

def text_blocks(xs: J.Json, +signature: String) -> J.Json:
  match xs:
    case J.Item{+block, rest}: J.Item{J.Object{J.str_field("type", "text", J.str_field("text", U.field(block, "text"), J.str_field("textSignature", signature, J.End{})))}, text_blocks(rest, signature)}
    case _: J.End{}

def summary_text(xs: J.Json) -> String:
  match xs:
    case J.Item{block, rest}: U.field(block, "text") ++ summary_text(rest)
    case _: ""

def one_block(+item: J.Json) -> J.Json:
  +kind = U.field(item, "type")
  tool = {J.Object{J.str_field("type", "toolCall", J.str_field("id", U.field(item, "call_id"), J.str_field("name", U.field(item, "name"), J.Field{"arguments", J.or_null(J.parse(U.field(item, "arguments"))), J.End{}})))} : J.Json}
  reasoning = {J.Object{J.str_field("type", "thinking", J.str_field("thinking", summary_text(J.array(J.get(item, "summary"))), J.str_field("thinkingSignature", J.encode(item), J.End{})))} : J.Json}
  Bool.pick(J.Json, String.eq(kind, "message"), text_blocks(J.array(J.get(item, "content")), U.field(item, "id")), Bool.pick(J.Json, String.eq(kind, "function_call"), J.Item{tool, J.End{}}, Bool.pick(J.Json, String.eq(kind, "reasoning"), J.Item{reasoning, J.End{}}, J.End{})))

def content_blocks(xs: J.Json) -> J.Json:
  match xs:
    case J.Item{item, rest}: J.append(one_block(item), content_blocks(rest))
    case _: J.End{}

def has_tool(xs: J.Json) -> Bool:
  match xs:
    case J.Item{item, rest}: String.eq(U.field(item, "type"), "function_call") || has_tool(rest)
    case _: False{}

def usage(+raw: J.Json) -> J.Json:
  +input = J.number(J.get(raw, "input_tokens"), 0n)
  +cached = J.number(J.get(J.get(raw, "input_tokens_details"), "cached_tokens"), 0n)
  +output = J.number(J.get(raw, "output_tokens"), 0n)
  zero_cost = J.or_null(J.parse("{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}"))
  counters = {J.Field{"input", J.Number{Nat.show(Nat.sub(input, cached))}, J.Field{"output", J.Number{Nat.show(output)}, J.Field{"cacheRead", J.Number{Nat.show(cached)}, J.Field{"cacheWrite", J.Number{"0"}, J.End{}}}}} : J.Json}
  J.Object{J.Field{"cost", zero_cost, J.Field{"totalTokens", J.Number{Nat.show(Nat.add(input, output))}, counters}}}

def assistant(+response: J.Json, model: String, timestamp: String) -> J.Json:
  +output = J.array(J.get(response, "output"))
  meta = J.str_field("role", "assistant", J.str_field("api", "openai-codex-responses", J.str_field("provider", "openai-codex", J.str_field("model", model, J.str_field("responseId", U.field(response, "id"), J.End{})))))
  details = {J.Field{"timestamp", J.Number{timestamp}, J.Field{"content", J.Array{content_blocks(output)}, J.Field{"usage", usage(J.get(response, "usage")), meta}}} : J.Json}
  J.Object{J.str_field("stopReason", Bool.pick(String, has_tool(output), "toolUse", "stop"), details)}

def user(text: String, timestamp: String) -> J.Json:
  J.Object{J.str_field("role", "user", J.str_field("content", text, J.Field{"timestamp", J.Number{timestamp}, J.End{}}))}

def tool_result(id: String, name: String, text: String, error: Bool, timestamp: String) -> J.Json:
  content = {J.Array{J.Item{J.Object{J.str_field("type", "text", J.str_field("text", text, J.End{}))}, J.End{}}} : J.Json}
  fields = J.str_field("role", "toolResult", J.str_field("toolCallId", id, J.str_field("toolName", name, J.End{})))
  J.Object{J.Field{"content", content, J.Field{"isError", J.Boolean{error}, J.Field{"timestamp", J.Number{timestamp}, fields}}}}
