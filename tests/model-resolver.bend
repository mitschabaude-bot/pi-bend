import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/thinking-levels.bend as Levels
import ../packages/coding-agent/src/core/model-runtime.bend as Models

# upstream test/model-resolver.test.ts: parseModelPattern and resolveCliModel.
# The runtime's getModels/hasConfiguredAuth mock becomes the model list and
# the authenticated provider names that resolveCliModelWith receives.
# Results are compared as "provider/id level warning error" summaries, so
# warnings upstream's assertions leave unchecked are pinned to its code.
def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def same(+actual: String,+expected: String,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),String.eq(actual,expected),_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name ++ "\n  expected " ++ expected ++ "\n  actual   " ++ actual))(Unit{})

def model(+id: String,provider: String,reasoning: Bool) -> Models.Model():
  Ai.Model{id,id,Ai.AnthropicMessagesApi{},provider,"https://invalid.local",reasoning,None{},Ai.InputText{} <> Nil{},None{},Ai.ModelCost{U32.to_f64(1),U32.to_f64(2),U32.to_f64(0),U32.to_f64(1),None{}},None{},U32.to_f64(128000),U32.to_f64(8192),None{},None{},None{}}
def allModels() -> List<&2,Models.Model()>:
  [model("claude-sonnet-4-5","anthropic",True{}),model("gpt-4o","openai",False{}),model("qwen/qwen3-coder:exacto","openrouter",True{}),model("openai/gpt-4o:extended","openrouter",False{})]
def withNeuralwatt() -> List<&2,Models.Model()>: List.append(&2,Models.Model(),allModels(),[model("some-base-model","neuralwatt",False{})])

def shownMaybe(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: text
def shownModel(value: Maybe<&2,Models.Model()>) -> String:
  match value:
    case None{}: "-"
    case Some{+found}: Models.modelProvider(found) ++ "/" ++ Models.modelId(found)
def shownLevel(value: Maybe<&2,Ai.ModelThinkingLevel>) -> String:
  match value:
    case None{}: "-"
    case Some{level}: Levels.name(level)
def parsed(result: Models.ParsedModelResult) -> String:
  match result:
    case Models.ParsedModelResult{found,level,warning}: shownModel(found) ++ " " ++ shownLevel(level) ++ " " ++ shownMaybe(warning)
def resolvedOf(resolution: Models.Resolution) -> Models.ResolveCliModelResult:
  match resolution:
    case Models.Resolved{result}: result
    case Models.AmbiguousAcross{cliModel,matches,hint}: Models.ambiguityMessage(cliModel,matches,hint)
def summary(result: Models.ResolveCliModelResult) -> String:
  match result:
    case Models.ResolveCliModelResult{found,level,warning,error}: shownModel(found) ++ " " ++ shownLevel(level) ++ " " ++ shownMaybe(warning) ++ " " ++ shownMaybe(error)
def reasoningOf(result: Models.ResolveCliModelResult) -> Bool:
  match result:
    case Models.ResolveCliModelResult{Some{Ai.Model{_,_,_,_,_,reasoning,_,_,_,_,_,_,_,_,_,_}},_,_,_}: reasoning
    case _: False{}
def resolve(provider: Maybe<&2,String>,cliModel: String,thinking: Maybe<&2,Ai.ModelThinkingLevel>,authed: List<&2,String>,models: List<&2,Models.Model()>) -> Models.ResolveCliModelResult:
  resolvedOf(Models.resolveCliModelWith(provider,cliModel,thinking,authed,models))
def bare(cliModel: String,authed: List<&2,String>,models: List<&2,Models.Model()>) -> String: summary(resolve(None{},cliModel,None{},authed,models))
def pattern(text: String) -> String: parsed(Models.parsePattern(text,allModels(),True{}))

def warningOf(result: Models.ParsedModelResult) -> String:
  match result:
    case Models.ParsedModelResult{_,_,warning}: shownMaybe(warning)
def sonnetAt(level: String) -> String: "anthropic/claude-sonnet-4-5 " ++ level ++ " -"
def glmAt(level: String) -> String: "neuralwatt/zai-org/GLM-5.1-FP8 " ++ level ++ " Model \"zai-org/GLM-5.1-FP8\" not found for provider \"neuralwatt\". Using custom model id. -"
def glmResolved(text: String) -> String: summary(resolve(None{},text,None{},Nil{},withNeuralwatt()))
def sonnetLevels(levels: List<&2,Ai.ModelThinkingLevel>) -> Bool:
  match levels:
    case Nil{}: True{}
    case level <> rest:
      +text = Levels.name(level)
      String.eq(pattern("sonnet:" ++ text),sonnetAt(text)) && sonnetLevels(rest)
def glmLevels(levels: List<&2,Ai.ModelThinkingLevel>) -> Bool:
  match levels:
    case Nil{}: True{}
    case level <> rest:
      +text = Levels.name(level)
      String.eq(glmResolved("neuralwatt/zai-org/GLM-5.1-FP8:" ++ text),glmAt(text)) && glmLevels(rest)

def solModels() -> List<&2,Models.Model()>: [model("gpt-5.6-sol","azure-openai-responses",False{}),model("gpt-5.6-sol","openai-codex",False{})]
def glmModels() -> List<&2,Models.Model()>: List.append(&2,Models.Model(),allModels(),[model("glm-5","zai",True{}),model("zai/glm-5","vercel-ai-gateway",True{})])
def mimoModels() -> List<&2,Models.Model()>: List.append(&2,Models.Model(),allModels(),[model("xiaomi/mimo-v2.5-pro","commandcode",False{}),model("mimo-v2.5-pro","xiaomi",False{})])
def providersOf(models: List<&2,Models.Model()>) -> List<&2,String>:
  match models:
    case Nil{}: Nil{}
    case found <> rest: Models.modelProvider(found) <> providersOf(rest)

def parseModelPattern() -> IO(Unit):
  do IO<Unit>:
    same(pattern("claude-sonnet-4-5"),"anthropic/claude-sonnet-4-5 - -","exact match returns model with undefined thinking level")
    same(pattern("sonnet"),"anthropic/claude-sonnet-4-5 - -","partial match returns best model with undefined thinking level")
    same(pattern("nonexistent"),"- - -","no match returns undefined model and thinking level")
    same(pattern("sonnet:high"),"anthropic/claude-sonnet-4-5 high -","sonnet:high returns sonnet with high thinking level")
    same(pattern("gpt-4o:medium"),"openai/gpt-4o medium -","gpt-4o:medium returns gpt-4o with medium thinking level")
    check(sonnetLevels(Levels.all()),"all valid thinking levels work")
    same(pattern("sonnet:random"),"anthropic/claude-sonnet-4-5 - Invalid thinking level \"random\" in pattern \"sonnet:random\". Using default instead.","sonnet:random returns sonnet with undefined thinking level and warning")
    same(warningOf(Models.parsePattern("gpt-4o:invalid",allModels(),True{})),"Invalid thinking level \"invalid\" in pattern \"gpt-4o:invalid\". Using default instead.","gpt-4o:invalid returns gpt-4o with undefined thinking level and warning")
    same(pattern("qwen/qwen3-coder:exacto"),"openrouter/qwen/qwen3-coder:exacto - -","qwen3-coder:exacto matches the model with undefined thinking level")
    same(pattern("openrouter/qwen/qwen3-coder:exacto"),"openrouter/qwen/qwen3-coder:exacto - -","openrouter/qwen/qwen3-coder:exacto matches with provider prefix")
    same(pattern("qwen/qwen3-coder:exacto:high"),"openrouter/qwen/qwen3-coder:exacto high -","qwen3-coder:exacto:high matches model with high thinking level")
    same(pattern("openrouter/qwen/qwen3-coder:exacto:high"),"openrouter/qwen/qwen3-coder:exacto high -","openrouter/qwen/qwen3-coder:exacto:high matches with provider and thinking level")
    same(pattern("openai/gpt-4o:extended"),"openrouter/openai/gpt-4o:extended - -","gpt-4o:extended matches the extended model with undefined thinking level")
    same(pattern("qwen/qwen3-coder:exacto:random"),"openrouter/qwen/qwen3-coder:exacto - Invalid thinking level \"random\" in pattern \"qwen/qwen3-coder:exacto:random\". Using default instead.","qwen3-coder:exacto:random returns model with undefined thinking level and warning")
    same(pattern("qwen/qwen3-coder:exacto:high:random"),"openrouter/qwen/qwen3-coder:exacto - Invalid thinking level \"random\" in pattern \"qwen/qwen3-coder:exacto:high:random\". Using default instead.","qwen3-coder:exacto:high:random returns model with undefined thinking level and warning")
    check(Bool.not(String.eq(pattern(""),"- - -")),"empty pattern matches via partial matching")
    same(pattern("sonnet:"),"anthropic/claude-sonnet-4-5 - Invalid thinking level \"\" in pattern \"sonnet:\". Using default instead.","pattern ending with colon treats empty suffix as invalid")

def resolveCliModel() -> IO(Unit):
  do IO<Unit>:
    same(bare("openai/gpt-4o",Nil{},allModels()),"openai/gpt-4o - - -","resolves --model provider/id without --provider")
    same(summary(resolve(Some{"openai"},"4o",None{},Nil{},allModels())),"openai/gpt-4o - - -","resolves fuzzy patterns within an explicit provider")
    same(bare("sonnet:high",Nil{},allModels()),"anthropic/claude-sonnet-4-5 high - -","supports --model <pattern>:<thinking> (without explicit --thinking)")
    same(bare("openai/gpt-4o:extended",Nil{},allModels()),"openrouter/openai/gpt-4o:extended - - -","prefers exact model id match over provider inference (OpenRouter-style ids)")
    same(summary(resolve(Some{"openai"},"gpt-4o:extended",None{},Nil{},allModels())),"openai/gpt-4o:extended - Model \"gpt-4o:extended\" not found for provider \"openai\". Using custom model id. -","does not strip invalid :suffix as thinking level in --model (treat as raw id)")
    same(summary(resolve(Some{"openrouter"},"openrouter/openai/ghost-model",None{},Nil{},allModels())),"openrouter/openai/ghost-model - Model \"openai/ghost-model\" not found for provider \"openrouter\". Using custom model id. -","allows custom model ids for explicit providers without double prefixing")
    same(summary(resolve(Some{"openai"},"gpt-4o",None{},Nil{},Nil{})),"- - - No models available. Check your installation or add models to models.json.","returns a clear error when there are no models")
    same(bare("gpt-5.6-sol",["openai-codex"],solModels()),"openai-codex/gpt-5.6-sol - - -","prefers the sole authenticated provider for an ambiguous bare exact model id")
    same(bare("gpt-5.6-sol",Nil{},solModels()),"- - - Model \"gpt-5.6-sol\" is ambiguous across providers: azure-openai-responses/gpt-5.6-sol, openai-codex/gpt-5.6-sol. No matching provider is authenticated. Use --provider or provider/model.","requires an explicit provider for an ambiguous bare exact model id without a unique authenticated provider")
    same(bare("gpt-5.6-sol",providersOf(solModels()),solModels()),"- - - Model \"gpt-5.6-sol\" is ambiguous across providers: azure-openai-responses/gpt-5.6-sol, openai-codex/gpt-5.6-sol. More than one matching provider is authenticated. Use --provider or provider/model.","an ambiguous bare exact model id with several authenticated providers names them all")
    same(bare("zai/glm-5",providersOf(glmModels()),glmModels()),"zai/glm-5 - - -","prefers provider/model split over gateway model with matching id")
    same(bare("xiaomi/mimo-v2.5-pro",["commandcode"],mimoModels()),"commandcode/xiaomi/mimo-v2.5-pro - - -","prefers an authenticated exact raw model id over an unauthenticated inferred provider")
    same(bare("openrouter/qwen",Nil{},allModels()),"openrouter/qwen/qwen3-coder:exacto - - -","resolves provider-prefixed fuzzy patterns (openrouter/qwen -> openrouter model)")
    +high : Models.ResolveCliModelResult = resolve(None{},"neuralwatt/zai-org/GLM-5.1-FP8:high",None{},Nil{},withNeuralwatt())
    check(String.eq(summary(high),glmAt("high")) && reasoningOf(high),"strips :thinking suffix from custom model id in fallback path")
    same(glmResolved("neuralwatt/zai-org/GLM-5.1-FP8"),"neuralwatt/zai-org/GLM-5.1-FP8 - Model \"zai-org/GLM-5.1-FP8\" not found for provider \"neuralwatt\". Using custom model id. -","custom model without thinking suffix works normally in fallback path")
    check(glmLevels(Levels.all()),"all valid thinking levels work in fallback path")
    same(glmResolved("neuralwatt/zai-org/GLM-5.1-FP8:banana"),"neuralwatt/zai-org/GLM-5.1-FP8:banana - Model \"zai-org/GLM-5.1-FP8:banana\" not found for provider \"neuralwatt\". Using custom model id. -","invalid thinking suffix on custom model is treated as part of model id")
    same(summary(resolve(Some{"neuralwatt"},"zai-org/GLM-5.1-FP8:high",None{},Nil{},withNeuralwatt())),glmAt("high"),"explicit --provider with custom model:thinking strips suffix correctly")
    same(summary(resolve(None{},"neuralwatt/zai-org/GLM-5.1-FP8:high",Some{Ai.Thinking{Ai.Medium{}}},Nil{},withNeuralwatt())),"neuralwatt/zai-org/GLM-5.1-FP8:high - Model \"zai-org/GLM-5.1-FP8:high\" not found for provider \"neuralwatt\". Using custom model id. -","with explicit --thinking, :suffix is kept as part of model id")

def main() -> IO(Unit):
  do IO<Unit>:
    parseModelPattern()
    resolveCliModel()
