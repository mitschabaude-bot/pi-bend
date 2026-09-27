import Base
import ../../../src/config.bend as Config
import ../../../src/utils/frontmatter.bend as Frontmatter
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/yaml.bend as Yaml

# pi v0.87.1 examples/extensions/subagent/agents.ts: agent discovery and
# configuration. Agents are markdown files with `name` and `description`
# frontmatter in the user's agent directory (<agentDir>/agents) and in the
# nearest project `.pi/agents` directory. The agent directory is a parameter
# (upstream reads getAgentDir() here); the extension resolves it once.

type AgentScope is Data:
  UserScope{}
  ProjectScope{}
  BothScope{}

def agentScopeName(scope: AgentScope) -> String:
  match scope:
    case UserScope{}: "user"
    case ProjectScope{}: "project"
    case BothScope{}: "both"

def agentScopeOf(name: String) -> Maybe<&2, AgentScope>:
  match name:
    case "user": Some{UserScope{}}
    case "project": Some{ProjectScope{}}
    case "both": Some{BothScope{}}
    case _: None{}

type AgentSource is Data:
  UserSource{}
  ProjectSource{}

def agentSourceName(source: AgentSource) -> String:
  match source:
    case UserSource{}: "user"
    case ProjectSource{}: "project"

type AgentConfig is Data:
  AgentConfig{name: String, description: String, tools: Maybe<&2, List<&2, String>>, model: Maybe<&2, String>, systemPrompt: String, source: AgentSource, filePath: String}

def agentName(agent: AgentConfig) -> String:
  match agent:
    case AgentConfig{name, _, _, _, _, _, _}: name

type AgentDiscoveryResult is Data:
  AgentDiscoveryResult{agents: List<&2, AgentConfig>, projectAgentsDir: Maybe<&2, String>}

# Frontmatter tools
# -----------------
# upstream parseToolList: `tools: read, bash` and `tools: [read, bash]` both
# name tools; other values (and non-string items) name none.

def textItems(values: List<&2, Yaml.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Yaml.Text{text} <> rest: text <> textItems(rest)
    case _ <> rest: textItems(rest)

def trimmedNonEmpty(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest:
      +trimmed = Text.trim(value)
      +others = trimmedNonEmpty(rest)
      Bool.pick(List<&2, String>, String.is_empty(trimmed), others, trimmed <> others)

def nonEmptyList(+tools: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  Bool.pick(Maybe<&2, List<&2, String>>, List.is_empty(&2, String, tools), None{}, Some{tools})

def parseToolList(value: Maybe<&2, Yaml.Value>) -> Maybe<&2, List<&2, String>>:
  match value:
    case Some{Yaml.Sequence{values}}: nonEmptyList(trimmedNonEmpty(textItems(values)))
    case Some{Yaml.Text{text}}: nonEmptyList(trimmedNonEmpty(Strings.split(text, ',')))
    case _: None{}

def textField(value: Maybe<&2, Yaml.Value>) -> Maybe<&2, String>:
  match value:
    case Some{Yaml.Text{text}}: Some{text}
    case _: None{}

# Loading a directory
# -------------------
# A file without a string name and description is skipped; unreadable files
# and directories are skipped; invalid YAML fails discovery (upstream's
# parseFrontmatter throws out of discoverAgents).

def agentFrom(+filePath: String, source: AgentSource, name: Maybe<&2, String>, description: Maybe<&2, String>, +fields: R.Record<Yaml.Value>, body: String) -> Maybe<&2, AgentConfig>:
  match name description:
    case Some{name} Some{description}: Some{AgentConfig{name, description, parseToolList(R.get(Yaml.Value, fields, "tools")), textField(R.get(Yaml.Value, fields, "model")), body, source, filePath}}
    case _ _: None{}

def parsedAgent(+filePath: String, source: AgentSource, parsed: Yaml.ResultOf(Frontmatter.Frontmatter)) -> Result<&2, &2, String, Maybe<&2, AgentConfig>>:
  match parsed:
    case Fail{error}: Fail{Yaml.errorMessage(error)}
    case Done{Frontmatter.Frontmatter{+fields, body}}: Done{agentFrom(filePath, source, textField(R.get(Yaml.Value, fields, "name")), textField(R.get(Yaml.Value, fields, "description")), fields, body)}

def readAgent(+filePath: String, source: AgentSource, content: Result<&2, &2, FS.Error, List<&2, U32>>) -> Result<&2, &2, String, Maybe<&2, AgentConfig>>:
  match content:
    case Fail{_}: Done{None{}}
    case Done{bytes}: parsedAgent(filePath, source, Frontmatter.parseFrontmatter(Utf8.decodeBuffer(bytes)))

def candidate(entry: FS.DirectoryEntry) -> Bool:
  match entry:
    case FS.DirectoryEntry{name, FS.RegularFile{}}: String.ends_with(name, ".md")
    case FS.DirectoryEntry{name, FS.SymbolicLink{}}: String.ends_with(name, ".md")
    case _: False{}

def entryName(entry: FS.DirectoryEntry) -> String:
  match entry:
    case FS.DirectoryEntry{name, _}: name

def withAgent(found: Result<&2, &2, String, Maybe<&2, AgentConfig>>, rest: Result<&2, &2, String, List<&2, AgentConfig>>) -> Result<&2, &2, String, List<&2, AgentConfig>>:
  match found rest:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{None{}} Done{agents}: Done{agents}
    case Done{Some{agent}} Done{agents}: Done{agent <> agents}

def loadCandidate(isCandidate: Bool, +filePath: String, source: AgentSource) -> IO(Result<&2, &2, String, Maybe<&2, AgentConfig>>):
  match isCandidate:
    case False{}: IO.pure(Result<&2, &2, String, Maybe<&2, AgentConfig>>, Done{None{}})
    case True{}:
      do IO<Result<&2, &2, String, Maybe<&2, AgentConfig>>>:
        content : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(filePath)
        return readAgent(filePath, source, content)

def loadEntries(+dir: String, +source: AgentSource, entries: List<&2, FS.DirectoryEntry>) -> IO(Result<&2, &2, String, List<&2, AgentConfig>>):
  match entries:
    case Nil{}: IO.pure(Result<&2, &2, String, List<&2, AgentConfig>>, Done{Nil{}})
    case +entry <> rest:
      do IO<Result<&2, &2, String, List<&2, AgentConfig>>>:
        found : Result<&2, &2, String, Maybe<&2, AgentConfig>> <- loadCandidate(candidate(entry), Path.join(dir, entryName(entry)), source)
        others : Result<&2, &2, String, List<&2, AgentConfig>> <- loadEntries(dir, source, rest)
        return withAgent(found, others)

def loadListed(+dir: String, source: AgentSource, listed: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>) -> IO(Result<&2, &2, String, List<&2, AgentConfig>>):
  match listed:
    case Fail{_}: IO.pure(Result<&2, &2, String, List<&2, AgentConfig>>, Done{Nil{}})
    case Done{entries}: loadEntries(dir, source, entries)

def loadAgentsFromDir(+dir: String, source: AgentSource) -> IO(Result<&2, &2, String, List<&2, AgentConfig>>):
  do IO<Result<&2, &2, String, List<&2, AgentConfig>>>:
    listed : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(dir)
    loadListed(dir, source, listed)

# Project agents
# --------------

def isDirectory(+path: String) -> IO(Bool):
  do IO<Bool>:
    kind : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind(path)
    return Result.default(&2, &2, FS.Error, Bool, Result.map(&2, &2, FS.Error, FS.FileKind, Bool, FS.isDirectory, kind), False{})

def parentDir(+path: String) -> String: Path.normalize(path ++ "/..")

# The nearest `.pi/agents` directory from cwd up to the root. The depth of
# cwd bounds the walk.
def findFrom(fuel: Nat, +currentDir: String) -> IO(Maybe<&2, String>):
  match fuel:
    case 0n: IO.pure(Maybe<&2, String>, None{})
    case 1n+rest:
      +candidateDir = Path.join(Path.join(currentDir, Config.configDirName()), "agents")
      +parent = parentDir(currentDir)
      do IO<Maybe<&2, String>>:
        found : Bool <- isDirectory(candidateDir)
        Bool.pick(Unit -> IO(Maybe<&2, String>), found,
          _ => IO.pure(Maybe<&2, String>, Some{candidateDir}),
          _ => Bool.pick(IO(Maybe<&2, String>), String.eq(parent, currentDir), IO.pure(Maybe<&2, String>, None{}), findFrom(rest, parent)))(Unit{})

def findNearestProjectAgentsDir(+cwd: String) -> IO(Maybe<&2, String>):
  findFrom(String.length(cwd) + 2n, cwd)

# Discovery
# ---------

def noAgents() -> IO(Result<&2, &2, String, List<&2, AgentConfig>>): IO.pure(Result<&2, &2, String, List<&2, AgentConfig>>, Done{Nil{}})

def userAgentsFor(+agentDir: String, scope: AgentScope) -> IO(Result<&2, &2, String, List<&2, AgentConfig>>):
  match scope:
    case ProjectScope{}: noAgents()
    case _: loadAgentsFromDir(Path.join(agentDir, "agents"), UserSource{})

def projectAgentsFor(projectAgentsDir: Maybe<&2, String>, scope: AgentScope) -> IO(Result<&2, &2, String, List<&2, AgentConfig>>):
  match scope projectAgentsDir:
    case UserScope{} _: noAgents()
    case _ None{}: noAgents()
    case _ Some{dir}: loadAgentsFromDir(dir, ProjectSource{})

# upstream's Map by name: a later agent replaces an earlier one of the same
# name in its position.
def keyed(agents: List<&2, AgentConfig>, +map: R.Record<AgentConfig>) -> R.Record<AgentConfig>:
  match agents:
    case Nil{}: map
    case +agent <> rest: keyed(rest, R.set(AgentConfig, map, agentName(agent), agent))

def mapValues(properties: List<&2, R.Property<AgentConfig>>) -> List<&2, AgentConfig>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{_, agent} <> rest: agent <> mapValues(rest)

def merged(scope: AgentScope, +user: List<&2, AgentConfig>, +project: List<&2, AgentConfig>) -> List<&2, AgentConfig>:
  match scope:
    case BothScope{}: mapValues(R.entries(AgentConfig, keyed(project, keyed(user, R.new(AgentConfig)))))
    case UserScope{}: mapValues(R.entries(AgentConfig, keyed(user, R.new(AgentConfig))))
    case ProjectScope{}: mapValues(R.entries(AgentConfig, keyed(project, R.new(AgentConfig))))

def discovered(scope: AgentScope, projectAgentsDir: Maybe<&2, String>, user: Result<&2, &2, String, List<&2, AgentConfig>>, project: Result<&2, &2, String, List<&2, AgentConfig>>) -> Result<&2, &2, String, AgentDiscoveryResult>:
  match user project:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{user} Done{project}: Done{AgentDiscoveryResult{merged(scope, user, project), projectAgentsDir}}

def discoverAgents(+agentDir: String, +cwd: String, +scope: AgentScope) -> IO(Result<&2, &2, String, AgentDiscoveryResult>):
  do IO<Result<&2, &2, String, AgentDiscoveryResult>>:
    +projectAgentsDir : Maybe<&2, String> <- findNearestProjectAgentsDir(cwd)
    user : Result<&2, &2, String, List<&2, AgentConfig>> <- userAgentsFor(agentDir, scope)
    project : Result<&2, &2, String, List<&2, AgentConfig>> <- projectAgentsFor(projectAgentsDir, scope)
    return discovered(scope, projectAgentsDir, user, project)

# upstream formatAgentList: up to maxItems agents as "name (source):
# description", and how many were left out.
type AgentList is Data:
  AgentList{text: String, remaining: Nat}

def listedAgent(agent: AgentConfig) -> String:
  match agent:
    case AgentConfig{name, description, _, _, _, source, _}: name ++ " (" ++ agentSourceName(source) ++ "): " ++ description

def listedAgents(agents: List<&2, AgentConfig>) -> List<&2, String>:
  match agents:
    case Nil{}: Nil{}
    case agent <> rest: listedAgent(agent) <> listedAgents(rest)

def formatAgentList(+agents: List<&2, AgentConfig>, maxItems: Nat) -> AgentList:
  +listed = List.take(&2, AgentConfig, agents, maxItems)
  Bool.pick(AgentList, List.is_empty(&2, AgentConfig, agents), AgentList{"none", 0n}, AgentList{String.join(listedAgents(listed), "; "), Nat.sub(List.length(&2, AgentConfig, agents), List.length(&2, AgentConfig, listed))})
