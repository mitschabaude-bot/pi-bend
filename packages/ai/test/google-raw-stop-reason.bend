import Base
import ../src/providers/google.models.bend as Catalog
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H

# pi-mono f07218c4d packages/ai/test/google-raw-stop-reason.test.ts, the
# Google Generative AI cases; the Google Vertex adapter is not ported. The SDK
# mock yields one chunk; natively it is the response body's one SSE event.
# The User-Agent cases read the SDK constructor's headers upstream and the
# wire request here.
def chunk(reason: String, functionCall: Bool) -> String:
  "data: {\"responseId\":\"google-response-id\",\"candidates\":[{\"finishReason\":\"" ++ reason ++ "\"" ++ Bool.pick(String, functionCall, ",\"content\":{\"parts\":[{\"functionCall\":{\"id\":\"call-1\",\"name\":\"echo\",\"args\":{\"value\":\"truncated\"}}}]}", "") ++ "}],\"usageMetadata\":{\"promptTokenCount\":1,\"candidatesTokenCount\":0,\"totalTokenCount\":1}}\n\n"

def respond(reason: String, functionCall: Bool) -> IO(H.Message()):
  +context = {H.context(H.user("hello") <> Nil{}) : H.Context()}
  do IO<H.Message()>:
    outcome : H.Outcome <- H.run(Catalog.model_gemini_2_5_flash(), context, H.direct(None{}, None{}), H.Respond{chunk(reason, functionCall) <> Nil{}})
    return H.messageOf(outcome)

def rawError() -> IO(Unit):
  +name = {"preserves raw Gemini finish reasons for Google Generative AI errors" : String}
  do IO<Unit>:
    +message : H.Message() <- respond("MALFORMED_FUNCTION_CALL", False{})
    H.equalStop(message, "error")
    A.equalText(H.rawStopReason(message), Some{"MALFORMED_FUNCTION_CALL"}, name ++ ": raw")
    A.equalText(H.errorMessage(message), Some{"Provider stopped with: MALFORMED_FUNCTION_CALL"}, name ++ ": message")
    A.pass(name)

def withTool(+reason: String, +stop: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +message : H.Message() <- respond(reason, True{})
    H.equalStop(message, stop)
    A.equalText(H.rawStopReason(message), Some{reason}, name ++ ": raw")
    A.check(H.toolCalled(message), name ++ ": tool call")
    A.pass(name)

def userAgent(headers: Maybe<&2, T.ProviderHeaders()>, +want: Maybe<&2, String>, +name: String) -> IO(Unit):
  +context = {H.context(H.user("hello") <> Nil{}) : H.Context()}
  +model = Catalog.model_gemini_2_5_flash()
  do IO<Unit>:
    +outcome : H.Outcome <- H.run(model, context, H.direct(Some{"test-api-key"}, headers), H.Send{})
    A.equalText(A.header(H.requestOf(outcome), "user-agent"), want, name)
    A.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    rawError()
    withTool("MAX_TOKENS", "length", "preserves MAX_TOKENS with a tool call as length for Google Generative AI")
    withTool("STOP", "toolUse", "maps STOP with a tool call to toolUse for Google Generative AI")
    +agent : String <- A.piUserAgent()
    userAgent(None{}, Some{agent}, "uses pi's User-Agent by default")
    userAgent(Some{A.headersOf(A.present("User-Agent", "custom-agent") <> Nil{})}, Some{"custom-agent"}, "lets explicit headers override the default User-Agent")
