import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/text.bend as Text
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/posix-path.bend as Path

# System prompt construction. Skills and project context files are supplied
# pre-loaded, as upstream; the skills prompt formatting is not ported yet, so
# skills are carried but rendered only when the port gains skills.

type ContextFile is Data:
  ContextFile{path: String, content: String}

type Skill is Data:
  Skill{name: String, description: String, filePath: String}

type BuildSystemPromptOptions is Data:
  BuildSystemPromptOptions{customPrompt: Maybe<&2, String>, forceSystemPrompt: Maybe<&2, String>, selectedTools: Maybe<&2, List<&2, String>>, toolSnippets: Maybe<&2, R.Record<String>>, toolGuidelines: Maybe<&2, R.Record<List<&2, String>>>, promptGuidelines: Maybe<&2, List<&2, String>>, appendSystemPrompt: Maybe<&2, String>, sections: Maybe<&2, R.Record<String>>, cwd: String, contextFiles: Maybe<&2, List<&2, ContextFile>>, skills: Maybe<&2, List<&2, Skill>>}

type NormalizedBuildSystemPromptOptions is Data:
  NormalizedBuildSystemPromptOptions{customPrompt: Maybe<&2, String>, forceSystemPrompt: Maybe<&2, String>, selectedTools: List<&2, String>, toolSnippets: R.Record<String>, toolGuidelines: R.Record<List<&2, String>>, promptGuidelines: List<&2, String>, appendSystemPrompt: String, sections: R.Record<String>, cwd: String, contextFiles: List<&2, ContextFile>, skills: List<&2, Skill>}

# Absolute paths of the installed pi documentation named in the prompt.
type DocsPaths is Data:
  DocsPaths{readme: String, docs: String, examples: String}

# Ordered prompt sections keyed by name. `preamble` is untagged text; every
# other section is wrapped in a tag of the same name.
def SystemPromptSections() -> Data: R.Record<String>

def options(cwd: String) -> BuildSystemPromptOptions:
  BuildSystemPromptOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, cwd, None{}, None{}}

def defaultTools() -> List<&2, String>: ["read", "bash", "edit", "write"]

def normalizeBuildSystemPromptOptions(input: BuildSystemPromptOptions) -> NormalizedBuildSystemPromptOptions:
  match input:
    case BuildSystemPromptOptions{customPrompt, forceSystemPrompt, selectedTools, toolSnippets, toolGuidelines, promptGuidelines, appendSystemPrompt, sections, cwd, contextFiles, skills}:
      NormalizedBuildSystemPromptOptions{customPrompt, forceSystemPrompt, Maybe.default(&2, List<&2, String>, selectedTools, defaultTools()), Maybe.default(&2, R.Record<String>, toolSnippets, R.new(String)), Maybe.default(&2, R.Record<List<&2, String>>, toolGuidelines, R.new(List<&2, String>)), Maybe.default(&2, List<&2, String>, promptGuidelines, Nil{}), Maybe.default(&2, String, appendSystemPrompt, ""), Maybe.default(&2, R.Record<String>, sections, R.new(String)), cwd, Maybe.default(&2, List<&2, ContextFile>, contextFiles, Nil{}), Maybe.default(&2, List<&2, Skill>, skills, Nil{})}

# Section names
# -------------

def nameStart(+c: Char) -> Bool: Char.is_lower(c)
def nameChar(+c: Char) -> Bool: Char.is_lower(c) || Char.is_digit(c) || Char.is_eq(c, '_') || Char.is_eq(c, '-')

def nameTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{c, rest}: nameChar(c) && nameTail(rest)

# ^[a-z][a-z0-9_-]*$ and never the preamble.
def validSectionName(name: String) -> Bool:
  match name:
    case SNil{}: False{}
    case "preamble": False{}
    case SCon{first, rest}: nameStart(first) && nameTail(rest)

def invalidSectionName(entries: List<&2, R.Property<String>>) -> Maybe<&2, String>:
  match entries:
    case Nil{}: None{}
    case R.Property{+name, _} <> rest: Bool.pick(Maybe<&2, String>, validSectionName(name), invalidSectionName(rest), Some{name})

# Rules
# -----

def contains(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case +first <> rest: String.eq(first, value) || contains(rest, value)

# Rules are trimmed, deduplicated and kept in first-seen order.
def addRule(+rules: List<&2, String>, rule: String) -> List<&2, String>:
  +normalized = String.trim(rule)
  Bool.pick(List<&2, String>, String.is_empty(normalized) || contains(rules, normalized), rules, normalized <> rules)

def addRules(additions: List<&2, String>, rules: List<&2, String>) -> List<&2, String>:
  match additions:
    case Nil{}: rules
    case rule <> rest: addRules(rest, addRule(rules, rule))

def fileOperationsRule(hasBash: Bool, hasPowerShell: Bool) -> List<&2, String>:
  match hasBash hasPowerShell:
    case True{} True{}: ["Use bash or PowerShell for file operations like listing, searching, and finding files"]
    case False{} True{}: ["Use PowerShell for file operations like listing, searching, and finding files"]
    case True{} False{}: ["Use bash for file operations like ls, rg, find"]
    case False{} False{}: Nil{}

def shellRules(+selectedTools: List<&2, String>) -> List<&2, String>:
  +hasShell = contains(selectedTools, "bash") || contains(selectedTools, "powershell")
  +hasListing = contains(selectedTools, "grep") || contains(selectedTools, "find") || contains(selectedTools, "ls")
  Bool.pick(List<&2, String>, hasShell && Bool.not(hasListing), fileOperationsRule(contains(selectedTools, "bash"), contains(selectedTools, "powershell")), Nil{})

def toolRules(selectedTools: List<&2, String>, +toolGuidelines: R.Record<List<&2, String>>, rules: List<&2, String>) -> List<&2, String>:
  match selectedTools:
    case Nil{}: rules
    case name <> rest: toolRules(rest, toolGuidelines, addRules(Maybe.default(&2, List<&2, String>, R.get(List<&2, String>, toolGuidelines, name), Nil{}), rules))

def bullets(rules: List<&2, String>) -> List<&2, String>:
  match rules:
    case Nil{}: Nil{}
    case rule <> rest: ("- " ++ rule) <> bullets(rest)

def buildRules(+selectedTools: List<&2, String>, toolGuidelines: R.Record<List<&2, String>>, promptGuidelines: List<&2, String>) -> String:
  +rules = addRules(["Show file paths clearly when working with files"], addRules(["Be concise in your responses"], addRules(promptGuidelines, toolRules(selectedTools, toolGuidelines, addRules(shellRules(selectedTools), Nil{})))))
  String.join(bullets(List.reverse(&2, String, rules)), "\n")

# Sections
# --------

def visibleTool(name: String, snippet: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match snippet:
    case None{}: rest
    case Some{SNil{}}: rest
    case Some{text}: ("- " ++ name ++ ": " ++ text) <> rest

def visibleTools(selectedTools: List<&2, String>, +toolSnippets: R.Record<String>) -> List<&2, String>:
  match selectedTools:
    case Nil{}: Nil{}
    case +name <> rest: visibleTool(name, R.get(String, toolSnippets, name), visibleTools(rest, toolSnippets))

def toolsText(lines: List<&2, String>) -> String:
  match lines:
    case Nil{}: "(none)\n\nIn addition to the tools above, you may have access to other custom tools depending on the project."
    case lines: String.join(lines, "\n") ++ "\n\nIn addition to the tools above, you may have access to other custom tools depending on the project."

def toolsSection(selectedTools: List<&2, String>, toolSnippets: R.Record<String>) -> String:
  toolsText(visibleTools(selectedTools, toolSnippets))

def defaultPreamble() -> String:
  "You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files."

def docsSection(readme: String, docs: String, examples: String) -> String:
  "Pi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):\n- Main documentation: " ++ readme ++ "\n- Additional docs: " ++ docs ++ "\n- Examples: " ++ examples ++ " (extensions, custom tools, SDK)\n- When reading pi docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory\n- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI (docs/tui.md, examples/extensions/), SDK (docs/sdk.md, examples/sdk/), keybindings (docs/keybindings.md), sessions (docs/session.md), extension development guidance (docs/extension-development-guidance.md, examples/extensions/)\n- When working on pi topics, read the docs and examples, and follow .md cross-references before implementing\n- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)"

def projectContext(files: List<&2, ContextFile>) -> List<&2, String>:
  match files:
    case Nil{}: Nil{}
    case ContextFile{path, content} <> rest: ("<project_instructions path=\"" ++ path ++ "\">\n" ++ content ++ "\n</project_instructions>") <> projectContext(rest)

def renderProjectContext(files: List<&2, ContextFile>) -> String:
  String.join("Project-specific instructions and guidelines:" <> projectContext(files), "\n\n")

def optionalSection(sections: R.Record<String>, name: String, text: String) -> R.Record<String>:
  match text:
    case SNil{}: sections
    case value: R.set(String, sections, name, value)

def customSections(custom: List<&2, R.Property<String>>, sections: R.Record<String>) -> R.Record<String>:
  match custom:
    case Nil{}: sections
    case R.Property{name, content} <> rest: customSections(rest, optionalSection(sections, name, content))

# Windows paths are shown with forward slashes.
def forwardSlashes(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'\\', rest}: SCon{'/', forwardSlashes(rest)}
    case SCon{c, rest}: SCon{c, forwardSlashes(rest)}

def tagProperty(preamble: Bool, +name: String, content: String) -> R.Property<String>:
  match preamble:
    case True{}: R.Property{name, content}
    case False{}: R.Property{name, "<" ++ name ++ ">\n" ++ content ++ "\n</" ++ name ++ ">"}

def tagged(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{+name, content} <> rest: tagProperty(String.eq(name, "preamble"), name, content) <> tagged(rest)

def defaultSections(+selectedTools: List<&2, String>, toolSnippets: R.Record<String>, toolGuidelines: R.Record<List<&2, String>>, promptGuidelines: List<&2, String>, docs: DocsPaths) -> R.Record<String>:
  match docs:
    case DocsPaths{readme, directory, examples}:
      R.set(String, R.set(String, R.set(String, R.set(String, R.new(String), "preamble", defaultPreamble()), "tools", toolsSection(selectedTools, toolSnippets)), "rules", buildRules(selectedTools, toolGuidelines, promptGuidelines)), "docs", docsSection(readme, directory, examples))

def preambleSections(customPrompt: Maybe<&2, String>, selectedTools: List<&2, String>, toolSnippets: R.Record<String>, toolGuidelines: R.Record<List<&2, String>>, promptGuidelines: List<&2, String>, docs: DocsPaths) -> R.Record<String>:
  match customPrompt:
    case Some{SCon{first, rest}}: R.set(String, R.new(String), "preamble", SCon{first, rest})
    case _: defaultSections(selectedTools, toolSnippets, toolGuidelines, promptGuidelines, docs)

def docsPaths(+packageDir: String) -> DocsPaths:
  DocsPaths{Path.join(packageDir, "README.md"), Path.join(packageDir, "docs"), Path.join(packageDir, "examples")}

def skillsSection(sections: R.Record<String>, selectedTools: List<&2, String>, skills: List<&2, Skill>) -> R.Record<String>:
  match skills:
    case Nil{}: sections
    case _: sections

def sectionsWithContext(sections: R.Record<String>, contextFiles: List<&2, ContextFile>) -> R.Record<String>:
  match contextFiles:
    case Nil{}: sections
    case files: R.set(String, sections, "project_context", renderProjectContext(files))

def assembled(normalized: NormalizedBuildSystemPromptOptions, docs: DocsPaths) -> R.Record<String>:
  match normalized:
    case NormalizedBuildSystemPromptOptions{customPrompt, _, +selectedTools, toolSnippets, toolGuidelines, promptGuidelines, appendSystemPrompt, R.Record{custom}, cwd, contextFiles, skills}:
      R.Record{tagged(R.entries(String, customSections(custom, R.set(String, skillsSection(sectionsWithContext(optionalSection(preambleSections(customPrompt, selectedTools, toolSnippets, toolGuidelines, promptGuidelines, docs), "addendum", appendSystemPrompt), contextFiles), selectedTools, skills), "cwd", forwardSlashes(cwd)))))}

# Build the ordered, independently replaceable sections of the structured
# system prompt. An invalid custom section name is an error.
def checkedSections(invalid: Maybe<&2, String>, normalized: NormalizedBuildSystemPromptOptions, docs: DocsPaths) -> Result<&2, &2, String, SystemPromptSections()>:
  match invalid:
    case Some{name}: Fail{"Invalid system prompt section name: " ++ name}
    case None{}: Done{assembled(normalized, docs)}

def customNames(normalized: NormalizedBuildSystemPromptOptions) -> List<&2, R.Property<String>>:
  match normalized:
    case NormalizedBuildSystemPromptOptions{_, _, _, _, _, _, _, R.Record{custom}, _, _, _}: custom

def sectionsOf(+normalized: NormalizedBuildSystemPromptOptions, docs: DocsPaths) -> Result<&2, &2, String, SystemPromptSections()>:
  checkedSections(invalidSectionName(customNames(normalized)), normalized, docs)

def buildSystemPromptSections(input: BuildSystemPromptOptions, docs: DocsPaths) -> Result<&2, &2, String, SystemPromptSections()>:
  sectionsOf(normalizeBuildSystemPromptOptions(input), docs)

# The complete prompt state. A forced prompt is opaque and lives in `content`
# with no sections; otherwise `content` is empty and the sections carry it.
type SystemPromptState is Data:
  SystemPromptState{content: String, sections: Maybe<&2, SystemPromptSections()>}

def forced(input: BuildSystemPromptOptions) -> Maybe<&2, String>:
  match input:
    case BuildSystemPromptOptions{_, force, _, _, _, _, _, _, _, _, _}: force

def stateOf(force: Maybe<&2, String>, input: BuildSystemPromptOptions, docs: DocsPaths) -> Result<&2, &2, String, SystemPromptState>:
  match force:
    case Some{content}: Done{SystemPromptState{content, None{}}}
    case None{}: Result.map(&2, &2, String, SystemPromptSections(), SystemPromptState, sections => SystemPromptState{"", Some{sections}}, buildSystemPromptSections(input, docs))

def buildSystemPromptState(+input: BuildSystemPromptOptions, docs: DocsPaths) -> Result<&2, &2, String, SystemPromptState>:
  stateOf(forced(input), input, docs)

def presentEntries(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<Maybe<&2, String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, Some{value}} <> presentEntries(rest)

def present(sections: SystemPromptSections()) -> R.Record<Maybe<&2, String>>:
  match sections:
    case R.Record{entries}: R.Record{presentEntries(entries)}

def systemMessage(state: SystemPromptState) -> Ai.SystemMessage<Ai.JsonValue>:
  match state:
    case SystemPromptState{content, sections}: Ai.SystemMessage{Ai.SystemText{content}, Maybe.map(&2, SystemPromptSections(), R.Record<Maybe<&2, String>>, present, sections), None{}, None{}, F.fromU32(0)}

# The prompt text, rendered exactly as the transcript's system message replays it.
def buildSystemPrompt(input: BuildSystemPromptOptions, docs: DocsPaths) -> Result<&2, &2, String, String>:
  Result.map(&2, &2, String, SystemPromptState, String, state => Text.renderComplete(Ai.JsonValue, systemMessage(state)), buildSystemPromptState(input, docs))

def changedEntry(old: Maybe<&2, Maybe<&2, String>>, +name: String, +text: String, +patch: List<&2, R.Property<Maybe<&2, String>>>) -> List<&2, R.Property<Maybe<&2, String>>>:
  match old:
    case Some{Some{+existing}}: Bool.pick(List<&2, R.Property<Maybe<&2, String>>>, String.eq(existing, text), patch, R.Property{name, Some{text}} <> patch)
    case _: R.Property{name, Some{text}} <> patch

# Diff the sections the model currently has against the desired ones. Returns
# a sections patch, or None when nothing changed.
def changed(+previous: R.Record<Maybe<&2, String>>, entries: List<&2, R.Property<String>>, patch: List<&2, R.Property<Maybe<&2, String>>>) -> List<&2, R.Property<Maybe<&2, String>>>:
  match entries:
    case Nil{}: patch
    case R.Property{+name, +text} <> rest: changed(previous, rest, changedEntry(R.get(Maybe<&2, String>, previous, name), name, text, patch))

def removed(+current: SystemPromptSections(), entries: List<&2, R.Property<Maybe<&2, String>>>, +patch: List<&2, R.Property<Maybe<&2, String>>>) -> List<&2, R.Property<Maybe<&2, String>>>:
  match entries:
    case Nil{}: patch
    case R.Property{+name, _} <> rest: removed(current, rest, Bool.pick(List<&2, R.Property<Maybe<&2, String>>>, Maybe.is_none(&2, String, R.get(String, current, name)), R.Property{name, None{}} <> patch, patch))

def patchOf(entries: List<&2, R.Property<Maybe<&2, String>>>) -> Maybe<&2, R.Record<Maybe<&2, String>>>:
  match entries:
    case Nil{}: None{}
    case values: Some{R.Record{values}}

def diffSystemPromptSections(+previous: R.Record<Maybe<&2, String>>, +current: SystemPromptSections()) -> Maybe<&2, R.Record<Maybe<&2, String>>>:
  match previous current:
    case R.Record{+old} R.Record{+entries}: patchOf(List.reverse(&2, R.Property<Maybe<&2, String>>, removed(R.Record{entries}, old, changed(R.Record{old}, entries, Nil{}))))

