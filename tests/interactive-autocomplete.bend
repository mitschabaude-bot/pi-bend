import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/collation.bend as Collation
import ../packages/tui/src/autocomplete.bend as AC
import ../packages/coding-agent/src/modes/interactive/interactive-mode.bend as Interactive
import ../packages/coding-agent/src/modes/interactive/model-search.bend as Search

# upstream test/interactive-mode-status.test.ts,
# "InteractiveMode.createBaseAutocompleteProvider". The session and login
# provider fakes become the argument-completion inputs; the suggestions come
# from the combined provider as in the editor.
def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def modelItems(models: List<&2, Search.ModelSearchItem>, prefix: String) -> IO(AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)):
  IO.pure(AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>), Interactive.modelArgumentItems(models, prefix))
type LoginFixture is Data: LoginFixture{collator: Maybe<&2, Collation.Collator>, options: List<&2, Interactive.AuthSelectorProvider>}
def loginItems(fixture: LoginFixture, prefix: String) -> IO(AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)):
  match fixture:
    case LoginFixture{collator, options}: IO.pure(AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>), Interactive.loginArgumentItems(collator, options, prefix))

def command(name: String, arguments: Callback.Callback<String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)>) -> AC.Command:
  AC.Slash{AC.SlashCommand{name, None{}, None{}, Some{arguments}}}
def suggestedBy(created: AC.ResultOf(AC.CombinedAutocompleteProvider), +line: String) -> IO(AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>)):
  match created:
    case Fail{error}: IO.pure(AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>), Fail{error})
    case Done{provider}: AC.getSuggestions(provider, [line], 0n, String.length(line), AC.Options{None{}, False{}})
def suggestions(commands: List<&2, AC.Command>, line: String) -> IO(AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>)):
  suggestedBy(AC.create(commands, "/tmp", "/tmp", AC.ScalarOrder{}, False{}), line)

def values(items: List<&2, AC.AutocompleteItem>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case AC.AutocompleteItem{value, _, _} <> rest: value <> values(rest)
def suggestedValues(result: AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>)) -> List<&2, String>:
  match result:
    case Done{Some{AC.AutocompleteSuggestions{items, _}}}: values(items)
    case _: Nil{}
def sameTexts(left: List<&2, String>, right: List<&2, String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> restA b <> restB: String.eq(a, b) && sameTexts(restA, restB)
    case _ _: False{}
def onlyItem(result: AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>), +value: String, +label: String, +description: String) -> Bool:
  match result:
    case Done{Some{AC.AutocompleteSuggestions{[AC.AutocompleteItem{v, l, Some{d}}], _}}}: String.eq(v, value) && String.eq(l, label) && String.eq(d, description)
    case _: False{}

def models() -> List<&2, Search.ModelSearchItem>:
  [Search.ModelSearchItem{"gpt-5.2-codex", "github-copilot", "GPT-5.2 Codex"}, Search.ModelSearchItem{"gpt-5.5", "openai-codex", "GPT-5.5"}]
def loginOptions() -> List<&2, Interactive.AuthSelectorProvider>:
  [Interactive.AuthSelectorProvider{"anthropic", "Anthropic", "oauth"}, Interactive.AuthSelectorProvider{"anthropic", "Anthropic", "api_key"}, Interactive.AuthSelectorProvider{"openai", "OpenAI", "api_key"}]
def loaded(result: Result<&2, &2, Collation.LoadError, Collation.Collator>) -> Maybe<&2, Collation.Collator>:
  match result:
    case Done{collator}: Some{collator}
    case Fail{_}: None{}

def main() -> IO(Unit):
  do IO<Unit>:
    +modelArguments : Callback.Callback<String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)> <- Callback.create(~List<&2, Search.ModelSearchItem>, ~String, ~AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>), ~modelItems, models())
    modelResult : AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>) <- suggestions([command("model", modelArguments)], "/model codexgpt")
    check(sameTexts(suggestedValues(modelResult), ["openai-codex/gpt-5.5", "github-copilot/gpt-5.2-codex"]), "matches model command arguments across provider/model order")
    Callback.dispose(String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>), modelArguments)
    collator : Result<&2, &2, Collation.LoadError, Collation.Collator> <- Collation.load("packages/runtime/data")
    +loginArguments : Callback.Callback<String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)> <- Callback.create(~LoginFixture, ~String, ~AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>), ~loginItems, LoginFixture{loaded(collator), loginOptions()})
    loginResult : AC.ResultOf(Maybe<&2, AC.AutocompleteSuggestions>) <- suggestions([command("login", loginArguments)], "/login subscription anthrop")
    check(onlyItem(loginResult, "anthropic", "anthropic", "Anthropic · subscription/API key"), "matches login command arguments by provider id and name")
    Callback.dispose(String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>), loginArguments)
