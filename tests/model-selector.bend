import Base
import ../packages/ai/src/providers/openai-codex.models.bend as Codex
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/modes/interactive/components/model-selector.bend as Picker
import ../packages/coding-agent/src/modes/interactive/commands.bend as Commands

def checkSelected(model: Maybe<&2,Models.Model()>) -> IO(Unit):
  match model:
    case None{}: IO.die(Unit,1,"model selector has no selection")
    case Some{model}:
      Bool.pick(Unit -> IO(Unit),String.contains(Models.reference(model),"openai-codex/"),_ => IO.print("authenticated model catalog selection: ok"),_ => IO.die(Unit,1,"wrong selected model"))(Unit{})
def check(state: Picker.State) -> IO(Unit): checkSelected(Picker.selected(state))
def main() -> IO(Unit):
  do IO<Unit>:
    check(Picker.create(Codex.OPENAI_CODEX_MODELS(),None{},"openai-codex",24n))
    checkSelected(Commands.exactModel(Codex.OPENAI_CODEX_MODELS(),"OPENAI-CODEX/GPT-5.3-CODEX-SPARK"))
    checkSelected(Commands.exactModel(Codex.OPENAI_CODEX_MODELS(),"gpt-5.3-codex-spark"))
