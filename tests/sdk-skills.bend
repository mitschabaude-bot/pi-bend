import Base
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/sdk.bend as Sdk
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/coding-agent/src/core/diagnostics.bend as D
import ../packages/coding-agent/src/core/resource-loader.bend as Resources
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/types.bend as ExtensionTypes

# upstream test/sdk-skills.test.ts ("createAgentSession skills option"): the
# default resource loader discovers skills in agentDir, and an injected
# ResourceLoader's skills are the session's. The check script passes a temp
# directory; each test uses its own subdirectory with skills/test-skill.

def check(ok: Bool, +name: String, +detail: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  " ++ detail))(Unit{})

def Created() -> Type: Result<&2, &1, String, Sdk.CreateAgentSessionResult>
def SessionPair() -> Type: Sdk.CreateAgentSessionResult & Session.AgentSession

def required(created: Created(), +name: String) -> IO(Sdk.CreateAgentSessionResult):
  match created:
    case Done{result}: IO.pure(Sdk.CreateAgentSessionResult, result)
    case Fail{message}: IO.die(Sdk.CreateAgentSessionResult, 1, "FAIL " ++ name ++ "\n  createAgentSession: " ++ message)

def requiredSession(result: Sessions.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{session}: IO.pure(Session.Session(), session)
    case Fail{error}: IO.die(Session.Session(), 1, Sessions.message(error))

def memorySession(+cwd: String) -> IO(Session.Session()):
  do IO<Session.Session()>:
    ids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(ids, cwd, Sessions.noOptions())
    requiredSession(created)

# upstream beforeEach: <tempDir>/skills/test-skill/SKILL.md.
def prepared(+tempDir: String) -> IO(Unit):
  +skillsDir = Path.join(Path.join(tempDir, "skills"), "test-skill")
  do IO<Unit>:
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(skillsDir)
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(Path.join(skillsDir, "SKILL.md"), "---\nname: test-skill\ndescription: A test skill for SDK tests.\n---\n\n# Test Skill\n\nThis is a test skill.\n")
    return Unit{}

def options(+tempDir: String, session: Session.Session(), loader: Maybe<&2, Resources.ResourceLoader>) -> Sdk.CreateAgentSessionOptions:
  Sdk.CreateAgentSessionOptions{Some{tempDir}, Some{tempDir}, None{}, None{}, None{}, Nil{}, None{}, None{}, None{}, loader, Some{session}, None{}, Nil{}}

def skillNames(skills: List<&2, Skills.Skill>) -> List<&2, String>:
  match skills:
    case Nil{}: Nil{}
    case Skills.Skill{name, _, _, _, _, _} <> rest: name <> skillNames(rest)

def containsName(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || containsName(rest, name)

def loaderSkills(loader: Maybe<&2, Resources.ResourceLoader>) -> IO(Resources.SkillsResult):
  match loader:
    case None{}: IO.pure(Resources.SkillsResult, Resources.SkillsResult{Nil{}, Nil{}})
    case Some{found}: Resources.getSkills(found)

# session.resourceLoader.getSkills()
def sessionSkills(pair: SessionPair()) -> IO(Resources.SkillsResult):
  match pair:
    case Tuple{result, +session}:
      do IO<Resources.SkillsResult>:
        loader : Maybe<&2, Resources.ResourceLoader> <- Session.resourceLoader(session)
        +skills : Resources.SkillsResult <- loaderSkills(loader)
        Sdk.dispose(result)
        return skills

def skillsOf(result: Resources.SkillsResult) -> List<&2, Skills.Skill>:
  match result:
    case Resources.SkillsResult{skills, _}: skills

def diagnosticsOf(result: Resources.SkillsResult) -> List<&2, D.ResourceDiagnostic>:
  match result:
    case Resources.SkillsResult{_, diagnostics}: diagnostics

def shownNames(names: List<&2, String>) -> String: "[" ++ String.join(names, ",") ++ "]"

# "should discover skills by default and expose them on session.skills"
def discoversSkillsByDefault(+base: String) -> IO(Unit):
  +name = {"should discover skills by default and expose them on session.skills" : String}
  do IO<Unit>:
    prepared(base)
    session : Session.Session() <- memorySession(base)
    created : Created() <- Sdk.createAgentSession(options(base, session, None{}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    skills : Resources.SkillsResult <- sessionSkills(Sdk.sessionOf(result))
    +names : List<&2, String> = skillNames(skillsOf(skills))
    check(Bool.not(List.is_empty(&2, String, names)) && containsName(names, "test-skill"), name, shownNames(names))

# A ResourceLoader with no resources but the given skills (upstream's object
# literal loaders).
def noExtensions(runtime: ExtensionTypes.ExtensionRuntime(), unit: Unit) -> IO(Resources.LoadExtensionsResult): IO.pure(Resources.LoadExtensionsResult, Resources.LoadExtensionsResult{Nil{}, Nil{}, runtime})
def givenSkills(skills: List<&2, Skills.Skill>, unit: Unit) -> IO(Resources.SkillsResult): IO.pure(Resources.SkillsResult, Resources.SkillsResult{skills, Nil{}})
def noPrompts(unit: Unit, input: Unit) -> IO(Resources.PromptsResult): IO.pure(Resources.PromptsResult, Resources.PromptsResult{Nil{}, Nil{}})
def noThemes(unit: Unit, input: Unit) -> IO(Resources.ThemesResult): IO.pure(Resources.ThemesResult, Resources.ThemesResult{Nil{}, Nil{}})
def noAgentsFiles(unit: Unit, input: Unit) -> IO(Resources.AgentsFilesResult): IO.pure(Resources.AgentsFilesResult, Resources.AgentsFilesResult{Nil{}})
def noSystemPrompt(unit: Unit, input: Unit) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def noSystemPromptSource(unit: Unit, input: Unit) -> IO(Maybe<&2, Resources.SourcePath>): IO.pure(Maybe<&2, Resources.SourcePath>, None{})
def noAppend(unit: Unit, input: Unit) -> IO(List<&2, String>): IO.pure(List<&2, String>, Nil{})
def noAppendSources(unit: Unit, input: Unit) -> IO(List<&2, Resources.SourcePath>): IO.pure(List<&2, Resources.SourcePath>, Nil{})
def ignoreExtend(unit: Unit, paths: Resources.ResourceExtensionPaths) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoreReload(unit: Unit, options: Resources.ResourceLoaderReloadOptions) -> IO(Unit): IO.pure(Unit, Unit{})

def loaderWith(skills: List<&2, Skills.Skill>) -> IO(Resources.ResourceLoader):
  do IO<Resources.ResourceLoader>:
    runtime : ExtensionTypes.ExtensionRuntime() <- Loader.createExtensionRuntime()
    a : C.Callback<Unit, Resources.LoadExtensionsResult> <- C.create(~ExtensionTypes.ExtensionRuntime(), ~Unit, ~Resources.LoadExtensionsResult, ~noExtensions, runtime)
    b : C.Callback<Unit, Resources.SkillsResult> <- C.create(~List<&2, Skills.Skill>, ~Unit, ~Resources.SkillsResult, ~givenSkills, skills)
    c : C.Callback<Unit, Resources.PromptsResult> <- C.create(~Unit, ~Unit, ~Resources.PromptsResult, ~noPrompts, Unit{})
    d : C.Callback<Unit, Resources.ThemesResult> <- C.create(~Unit, ~Unit, ~Resources.ThemesResult, ~noThemes, Unit{})
    e : C.Callback<Unit, Resources.AgentsFilesResult> <- C.create(~Unit, ~Unit, ~Resources.AgentsFilesResult, ~noAgentsFiles, Unit{})
    f : C.Callback<Unit, Maybe<&2, String>> <- C.create(~Unit, ~Unit, ~Maybe<&2, String>, ~noSystemPrompt, Unit{})
    g : C.Callback<Unit, Maybe<&2, Resources.SourcePath>> <- C.create(~Unit, ~Unit, ~Maybe<&2, Resources.SourcePath>, ~noSystemPromptSource, Unit{})
    h : C.Callback<Unit, List<&2, String>> <- C.create(~Unit, ~Unit, ~List<&2, String>, ~noAppend, Unit{})
    i : C.Callback<Unit, List<&2, Resources.SourcePath>> <- C.create(~Unit, ~Unit, ~List<&2, Resources.SourcePath>, ~noAppendSources, Unit{})
    j : C.Callback<Resources.ResourceExtensionPaths, Unit> <- C.create(~Unit, ~Resources.ResourceExtensionPaths, ~Unit, ~ignoreExtend, Unit{})
    k : C.Callback<Resources.ResourceLoaderReloadOptions, Unit> <- C.create(~Unit, ~Resources.ResourceLoaderReloadOptions, ~Unit, ~ignoreReload, Unit{})
    return Resources.ResourceLoader{a, b, c, d, e, f, g, h, i, j, k}

# "should have empty skills when resource loader returns none (--no-skills)"
def emptySkillsFromLoader(+base: String) -> IO(Unit):
  +name = {"should have empty skills when resource loader returns none (--no-skills)" : String}
  do IO<Unit>:
    prepared(base)
    session : Session.Session() <- memorySession(base)
    loader : Resources.ResourceLoader <- loaderWith(Nil{})
    created : Created() <- Sdk.createAgentSession(options(base, session, Some{loader}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    +skills : Resources.SkillsResult <- sessionSkills(Sdk.sessionOf(result))
    check(List.is_empty(&2, Skills.Skill, skillsOf(skills)) && List.is_empty(&2, D.ResourceDiagnostic, diagnosticsOf(skills)), name, shownNames(skillNames(skillsOf(skills))))

# upstream createSyntheticSourceInfo("/fake/path/SKILL.md", { source: "sdk" }).
def customSkill() -> Skills.Skill:
  Skills.Skill{"custom-skill", "A custom skill", "/fake/path/SKILL.md", "/fake/path", Skills.SourceInfo{"/fake/path/SKILL.md", "sdk", Skills.Temporary{}, Skills.TopLevel{}, None{}}, False{}}

def sameSourceInfo(left: Skills.SourceInfo, right: Skills.SourceInfo) -> Bool:
  match left right:
    case Skills.SourceInfo{p1, s1, Skills.Temporary{}, Skills.TopLevel{}, None{}} Skills.SourceInfo{p2, s2, Skills.Temporary{}, Skills.TopLevel{}, None{}}: String.eq(p1, p2) && String.eq(s1, s2)
    case _ _: False{}

def sameSkill(left: Skills.Skill, right: Skills.Skill) -> Bool:
  match left right:
    case Skills.Skill{n1, d1, f1, b1, i1, m1} Skills.Skill{n2, d2, f2, b2, i2, m2}: String.eq(n1, n2) && String.eq(d1, d2) && String.eq(f1, f2) && String.eq(b1, b2) && sameSourceInfo(i1, i2) && Bool.not(Bool.xor(m1, m2))

def onlySkill(skills: List<&2, Skills.Skill>, +expected: Skills.Skill) -> Bool:
  match skills:
    case [found]: sameSkill(found, expected)
    case _: False{}

# "should use provided skills when resource loader supplies them"
def providedSkillsFromLoader(+base: String) -> IO(Unit):
  +name = {"should use provided skills when resource loader supplies them" : String}
  do IO<Unit>:
    prepared(base)
    session : Session.Session() <- memorySession(base)
    loader : Resources.ResourceLoader <- loaderWith([customSkill()])
    created : Created() <- Sdk.createAgentSession(options(base, session, Some{loader}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    +skills : Resources.SkillsResult <- sessionSkills(Sdk.sessionOf(result))
    check(onlySkill(skillsOf(skills), customSkill()) && List.is_empty(&2, D.ResourceDiagnostic, diagnosticsOf(skills)), name, shownNames(skillNames(skillsOf(skills))))

def runIn(+base: String) -> IO(Unit):
  do IO<Unit>:
    discoversSkillsByDefault(Path.join(base, "1"))
    emptySkillsFromLoader(Path.join(base, "2"))
    providedSkillsFromLoader(Path.join(base, "3"))

def run(args: List<String>) -> IO(Unit):
  match args:
    case base <> Nil{}: runIn(base)
    case _: IO.die(Unit, 1, "usage: sdk-skills <temp-dir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
