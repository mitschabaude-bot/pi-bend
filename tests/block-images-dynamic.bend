import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/f64.bend as F

def Messages() -> Data: Agent.AgentMessageArray(Value.Value,Runtime.Details(),Runtime.Custom())
def Converted() -> Data: Result<&2,&2,Runtime.Error(),List<&2,Ai.Message<Value.Value,Value.Value,Value.Value,Runtime.Details()>>>

def messages() -> Messages():
  [Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{"caption",None{}}},Ai.TextImageImage{Ai.ImageContent{"cGl4ZWw=","image/png"}}]},F.fromU32(1)}}}]

def imageState(blocks: List<&2,Ai.TextImageContent>) -> String:
  match blocks:
    case Ai.TextImageText{Ai.TextContent{"caption",_}} <> Ai.TextImageImage{_} <> Nil{}: "visible"
    case Ai.TextImageText{Ai.TextContent{"caption",_}} <> Ai.TextImageText{Ai.TextContent{"Image reading is disabled.",_}} <> Nil{}: "blocked"
    case _: "unexpected"

def observed(result: Converted()) -> IO(String):
  match result:
    case Done{Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks},_}} <> _}: IO.pure(String,imageState(blocks))
    case _: IO.die(String,1,"image conversion did not return a user message")

def updated(result: Settings.Outcome(Settings.SettingsManager)) -> IO(Settings.SettingsManager):
  match result:
    case Done{settings}: IO.pure(Settings.SettingsManager,settings)
    case Fail{_}: IO.die(Settings.SettingsManager,1,"could not update blockImages")

def manager(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case Tuple{_,settings}: settings

def check(actual: String,expected: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),String.eq(actual,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"blockImages did not affect the next conversion"))(Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    pair : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(),Settings.options())
    +initial : Settings.SettingsManager = manager(pair)
    +settings : Ref.Ref<Settings.SettingsManager> <- Ref.new(Settings.SettingsManager,initial)
    +converter : Runtime.Converter() <- Runtime.createSettingsConverter(settings)
    first : Converted() <- Callback.call(Messages(),Converted(),converter,messages())
    visible : String <- observed(first)
    check(visible,"visible")
    current : Settings.SettingsManager <- Ref.read(Settings.SettingsManager,settings)
    blocked : Settings.SettingsManager <- updated(Settings.setBlockImages(True{},current))
    Ref.write(Settings.SettingsManager,settings,blocked)
    second : Converted() <- Callback.call(Messages(),Converted(),converter,messages())
    hidden : String <- observed(second)
    check(hidden,"blocked")
    current : Settings.SettingsManager <- Ref.read(Settings.SettingsManager,settings)
    unblocked : Settings.SettingsManager <- updated(Settings.setBlockImages(False{},current))
    Ref.write(Settings.SettingsManager,settings,unblocked)
    third : Converted() <- Callback.call(Messages(),Converted(),converter,messages())
    visibleAgain : String <- observed(third)
    check(visibleAgain,"visible")
    Runtime.disposeConverter(converter)
    final : Settings.SettingsManager <- Ref.dispose(Settings.SettingsManager,settings)
    IO.print("blockImages follows settings changes between conversions")
