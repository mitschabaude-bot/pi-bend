import Base
import ../src/api/google-shared.bend as Shared
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H

# pi-mono f07218c4d packages/ai/test/google-thinking-level-map.test.ts, the
# Google Generative AI cases; the Google Vertex adapter is not ported.
def mapping(level: T.ModelThinkingLevel, value: Maybe<&2, T.Nullable<String>>) -> T.ThinkingLevelMapping: T.ThinkingLevelMapping{level, value}

def present(level: T.ThinkingLevel, value: String) -> T.ThinkingLevelMapping: mapping(T.Thinking{level}, Some{T.PresentValue{value}})

def absent(level: T.ModelThinkingLevel) -> T.ThinkingLevelMapping: mapping(level, Some{T.NullValue{}})

def googleModel(+id: String, levels: List<&2, T.ThinkingLevelMapping>) -> T.Model<T.JsonValue>:
  H.model(T.GoogleGenerativeAiApi{}, id, id, "test-google", "https://example.invalid/v1beta", False{}, 4096, 128000, Some{T.ThinkingLevelMap{levels}})

def levelName(result: Result<&2, &2, String, T.ThinkingLevel>) -> String:
  match result:
    case Done{level}: Shared.modelLevelName(level)
    case Fail{message}: "error: " ++ message

def resolves(+model: T.Model<T.JsonValue>, +level: T.ThinkingLevel, want: String) -> IO(Unit):
  A.equalText(Some{levelName(Shared.resolveGoogleThinkingLevel(model, level))}, Some{want}, "resolve " ++ Shared.modelLevelName(level))

def mapped(+value: String, +want: String) -> IO(Unit):
  +model = googleModel("gemini-3.7-flash", present(T.High{}, value) <> present(T.XHigh{}, value) <> present(T.Max{}, value) <> Nil{})
  do IO<Unit>:
    resolves(model, T.High{}, want)
    resolves(model, T.XHigh{}, want)
    resolves(model, T.Max{}, want)

def exhaustive() -> IO(Unit):
  +plain = googleModel("gemini-3.7-flash", Nil{})
  do IO<Unit>:
    resolves(plain, T.Minimal{}, "minimal")
    resolves(plain, T.Low{}, "low")
    resolves(plain, T.Medium{}, "medium")
    resolves(plain, T.High{}, "high")
    mapped("minimal", "minimal")
    mapped("low", "low")
    mapped("medium", "medium")
    mapped("high", "high")
    mapped("MINIMAL", "minimal")
    mapped("LOW", "low")
    mapped("MEDIUM", "medium")
    mapped("HIGH", "high")
    resolves(googleModel("gemini-3.7-flash", present(T.XHigh{}, "extreme") <> Nil{}), T.XHigh{}, "error: Unsupported Google thinking level mapping for test-google/gemini-3.7-flash: xhigh -> extreme")
    resolves(plain, T.Max{}, "error: Unsupported Google thinking level mapping for test-google/gemini-3.7-flash: max -> undefined")
    A.pass("exhaustively resolves supported logical levels and mapping values")

def budgets(high: U32) -> T.ThinkingBudgets: T.ThinkingBudgets{None{}, None{}, None{}, Some{U32.to_f64(high)}}

def gemini3Levels() -> List<&2, T.ThinkingLevelMapping>:
  absent(T.Off{}) <> absent(T.Thinking{T.Minimal{}}) <> present(T.Low{}, "low") <> present(T.Medium{}, "medium") <> present(T.High{}, "high") <> absent(T.Thinking{T.XHigh{}}) <> absent(T.Thinking{T.Max{}}) <> Nil{}

def capture(+model: T.Model<T.JsonValue>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>) -> IO(Maybe<&2, T.JsonValue>):
  +context = H.hello()
  do IO<Maybe<&2, T.JsonValue>>:
    +outcome : H.Outcome <- H.runSimple(model, context, H.simple(Some{"test"}, reasoning, budgets, None{}), H.Capture{})
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    A.check(A.contains(H.errorMessage(message), "payload captured"), "payload captured: " ++ A.showMaybe(H.errorMessage(message)))
    return A.pathOf(["config", "thinkingConfig"], H.payloadOf(outcome))

def thinkingConfig(+model: T.Model<T.JsonValue>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>, +want: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    config : Maybe<&2, T.JsonValue> <- capture(model, reasoning, budgets)
    A.equalJson(config, want, name)
    A.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    exhaustive()
    thinkingConfig(googleModel("gemini-3.8-flash", gemini3Levels()), None{}, None{}, "{\"thinkingLevel\":\"LOW\"}", "uses the lowest supported Google Generative AI level when reasoning is omitted")
    thinkingConfig(googleModel("gemini-3.1-pro-preview", gemini3Levels()), Some{T.Medium{}}, None{}, "{\"includeThoughts\":true,\"thinkingLevel\":\"MEDIUM\"}", "preserves native medium effort for Gemini 3.1 Pro on Google Generative AI")
    thinkingConfig(googleModel("gemini-2.5-flash", Nil{}), None{}, None{}, "{\"thinkingBudget\":0}", "disables Gemini 2.5 thinking when reasoning is omitted on Google Generative AI")
    thinkingConfig(googleModel("gemini-3.7-flash", present(T.XHigh{}, "high") <> present(T.Max{}, "high") <> Nil{}), Some{T.XHigh{}}, None{}, "{\"includeThoughts\":true,\"thinkingLevel\":\"HIGH\"}", "maps Google Generative AI xhigh to a supported level")
    thinkingConfig(googleModel("gemini-3.7-flash", present(T.XHigh{}, "high") <> present(T.Max{}, "high") <> Nil{}), Some{T.Max{}}, None{}, "{\"includeThoughts\":true,\"thinkingLevel\":\"HIGH\"}", "maps Google Generative AI max to a supported level")
    thinkingConfig(googleModel("gemini-3.7-flash", present(T.High{}, "LOW") <> Nil{}), Some{T.High{}}, None{}, "{\"includeThoughts\":true,\"thinkingLevel\":\"LOW\"}", "honors uppercase provider values for standard Google Generative AI levels")
    thinkingConfig(googleModel("gemini-2.5-flash", present(T.XHigh{}, "high") <> Nil{}), Some{T.XHigh{}}, Some{budgets(1234)}, "{\"includeThoughts\":true,\"thinkingBudget\":1234}", "uses mapped Google Generative AI levels for token budgets")
