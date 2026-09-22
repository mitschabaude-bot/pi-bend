import Base
import ../packages/coding-agent/src/core/system-prompt.bend as Prompt
import ../packages/runtime/src/record.bend as R

# Fixture for system-prompt: `build <scenario>` prints the prompt for a named
# upstream test scenario; `sections <scenario>` prints one line per section
# as `name<TAB>text` with newlines escaped; `diff` prints a sections patch.

def docs() -> Prompt.DocsPaths: Prompt.docsPaths("/opt/pi")

def snippets() -> R.Record<String>:
  R.Record{[R.Property{"read", "Read file contents"}, R.Property{"bash", "Execute bash commands (ls, grep, find, etc.)"}, R.Property{"edit", "Make precise file edits with exact text replacement, including multiple disjoint edits in one call"}, R.Property{"write", "Create or overwrite files"}]}

def guidelines() -> R.Record<List<&2, String>>:
  R.Record{[R.Property{"read", ["Use read to examine files instead of cat or sed."]}, R.Property{"bash", ["You can inspect PI_* environment variables for current model and session details."]}, R.Property{"edit", ["Use edit for precise changes (edits[].oldText must match exactly)"]}, R.Property{"write", ["Use write only for new files or complete rewrites."]}]}

def base(cwd: String) -> Prompt.BuildSystemPromptOptions:
  Prompt.BuildSystemPromptOptions{None{}, None{}, Some{Nil{}}, None{}, None{}, None{}, None{}, None{}, cwd, Some{Nil{}}, Some{Nil{}}}

def scenario(name: String) -> Prompt.BuildSystemPromptOptions:
  match name:
    case "empty-tools": base("/work")
    case "custom-prefix": Prompt.BuildSystemPromptOptions{Some{"You are Exact."}, None{}, Some{Nil{}}, None{}, None{}, None{}, None{}, None{}, "/tmp", Some{Nil{}}, Some{Nil{}}}
    case "forced": Prompt.BuildSystemPromptOptions{None{}, Some{"exact"}, None{}, None{}, None{}, None{}, None{}, None{}, "/tmp", None{}, None{}}
    case "sections": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{Nil{}}, None{}, None{}, None{}, Some{"Custom instructions"}, None{}, "/tmp", Some{[Prompt.ContextFile{"/tmp/AGENTS.md", "Project rules"}]}, Some{Nil{}}}
    case "default-tools": Prompt.BuildSystemPromptOptions{None{}, None{}, None{}, Some{snippets()}, Some{guidelines()}, None{}, None{}, None{}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "custom-snippet": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{["read", "custom_tool"]}, Some{R.Record{[R.Property{"read", "Read file contents"}, R.Property{"custom_tool", "Does custom things"}]}}, None{}, None{}, None{}, None{}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "missing-snippet": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{["read", "custom_tool"]}, Some{R.Record{[R.Property{"read", "Read file contents"}]}}, None{}, None{}, None{}, None{}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "prompt-guidelines": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{Nil{}}, None{}, None{}, Some{["Always run tests.", "  Always run tests.  ", "", "Prefer small commits."]}, None{}, None{}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "bash-only": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{["bash"]}, None{}, None{}, None{}, None{}, None{}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "custom-section": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{Nil{}}, None{}, None{}, None{}, None{}, Some{R.Record{[R.Property{"memory", "Remember this"}, R.Property{"empty", ""}]}}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "bad-section": Prompt.BuildSystemPromptOptions{None{}, None{}, Some{Nil{}}, None{}, None{}, None{}, None{}, Some{R.Record{[R.Property{"Bad Name", "x"}]}}, "/work", Some{Nil{}}, Some{Nil{}}}
    case "windows-cwd": base("C:\\work\\repo")
    case _: base("/work")

def escaped(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'\n', rest}: "\\n" ++ escaped(rest)
    case SCon{c, rest}: SCon{c, escaped(rest)}

def sectionLines(entries: List<&2, R.Property<String>>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case R.Property{name, text} <> rest:
      do IO<Unit>:
        IO.print(name ++ "\t" ++ escaped(text))
        sectionLines(rest)

def printSections(result: Result<&2, &2, String, Prompt.SystemPromptSections()>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error:" ++ error)
    case Done{R.Record{entries}}: sectionLines(entries)

def printPrompt(result: Result<&2, &2, String, String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error:" ++ error)
    case Done{text}: IO.print(text)

def patchLines(entries: List<&2, R.Property<Maybe<&2, String>>>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case R.Property{name, None{}} <> rest:
      do IO<Unit>:
        IO.print(name ++ "\tnull")
        patchLines(rest)
    case R.Property{name, Some{text}} <> rest:
      do IO<Unit>:
        IO.print(name ++ "\t" ++ escaped(text))
        patchLines(rest)

def printPatch(patch: Maybe<&2, R.Record<Maybe<&2, String>>>) -> IO(Unit):
  match patch:
    case None{}: IO.print("unchanged")
    case Some{R.Record{entries}}: patchLines(entries)

def previous() -> R.Record<Maybe<&2, String>>:
  R.Record{[R.Property{"preamble", Some{"old"}}, R.Property{"tools", Some{"<tools>\nsame\n</tools>"}}, R.Property{"removed", Some{"gone"}}]}

def current() -> Prompt.SystemPromptSections():
  R.Record{[R.Property{"preamble", "new"}, R.Property{"tools", "<tools>\nsame\n</tools>"}, R.Property{"added", "<added>\nhi\n</added>"}]}

def run(values: List<String>) -> IO(Unit):
  match values:
    case "build" <> name <> Nil{}: printPrompt(Prompt.buildSystemPrompt(scenario(name), docs()))
    case "sections" <> name <> Nil{}: printSections(Prompt.buildSystemPromptSections(scenario(name), docs()))
    case "diff" <> Nil{}: printPatch(Prompt.diffSystemPromptSections(previous(), current()))
    case "diff-same" <> Nil{}: printPatch(Prompt.diffSystemPromptSections(R.Record{[R.Property{"preamble", Some{"same"}}]}, R.Record{[R.Property{"preamble", "same"}]}))
    case _: IO.die(Unit, 2, "usage: build|sections <scenario> | diff | diff-same")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
