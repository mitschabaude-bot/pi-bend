import Base
import ./diagnostics.bend as D
import ./footer-data-provider.bend as Git
import ./system-prompt.bend as Prompt
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as R
import ./package-manager.bend as PackageManager
import ./skills.bend as Skills
import ./prompt-templates.bend as Templates
import ./settings-manager.bend as Settings
import ./extensions/types.bend as ExtensionTypes
import ./extensions/loader.bend as ExtensionLoader
import ../modes/interactive/theme/theme.bend as Theme
import ../modes/interactive/theme/color.bend as Color

# upstream core/resource-loader.ts: the ResourceLoader interface a session
# takes its extensions, skills, prompt templates, themes, context files and
# system prompt from, and the DefaultResourceLoader that discovers them.
# Project context files (upstream loadProjectContextFiles)
# ------------------------------------------------------

type Options is Data:
  Options{cwd: String,agentDir: String}
type ContextFiles is Data:
  ContextFiles{files: List<&2,Prompt.ContextFile>,diagnostics: List<&2,D.ResourceDiagnostic>}
type Candidate is Data:
  Candidate{file: Maybe<&2,Prompt.ContextFile>,diagnostics: List<&2,D.ResourceDiagnostic>}
def stripBom(content: String) -> String:
  match content:
    case SCon{Chr{65279},rest}: rest
    case other: other
def systemMessage(error: FS.Error) -> String:
  match error:
    case FS.System{_,message}: message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close
    case FS.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
def decoded(value: Result<&2,&2,Utf8.Error,String>,path: String) -> Candidate:
  match value:
    case Fail{_}: Candidate{None{},D.warning("Invalid UTF-8 in context file",path) <> Nil{}}
    case Done{content}: Candidate{Some{Prompt.ContextFile{path,stripBom(content)}},Nil{}}
def readCandidate(value: Result<&2,&2,FS.Error,List<&2,U32>>,path: String) -> Candidate:
  match value:
    case Fail{cause}: Candidate{None{},D.warning(systemMessage(cause),path) <> Nil{}}
    case Done{bytes}: decoded(Utf8.decodeWith(Utf8.Preserve{},bytes),path)
def candidateKind(kind: Result<&2,&2,FS.Error,FS.FileKind>,+path: String) -> IO(Candidate):
  match kind:
    case Done{FS.RegularFile{}}:
      do IO<Candidate>:
        value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        return readCandidate(value,path)
    case Fail{FS.System{2,_}}: IO.pure(Candidate,Candidate{None{},Nil{}})
    case Fail{cause}: IO.pure(Candidate,Candidate{None{},D.warning(systemMessage(cause),path) <> Nil{}})
    case _: IO.pure(Candidate,Candidate{None{},Nil{}})
def selected(candidate: Candidate) -> Bool:
  match candidate:
    case Candidate{Some{_},_}: True{}
    case _: False{}
def combined(candidate: Candidate,earlier: List<&2,D.ResourceDiagnostic>) -> Candidate:
  match candidate:
    case Candidate{file,issues}: Candidate{file,List.append(&2,D.ResourceDiagnostic,earlier,issues)}
def candidateIssues(value: Candidate) -> List<&2,D.ResourceDiagnostic>:
  match value:
    case Candidate{_,issues}: issues
def candidates(names: List<&2,String>,+directory: String,issues: List<&2,D.ResourceDiagnostic>) -> IO(Candidate):
  match names:
    case Nil{}: IO.pure(Candidate,Candidate{None{},issues})
    case name <> rest:
      do IO<Candidate>:
        +path : String = Path.join(directory,name)
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        +value : Candidate <- candidateKind(kind,path)
        +all : Candidate = combined(value,issues)
        Bool.pick(Unit -> IO(Candidate),selected(value),_ => IO.pure(Candidate,all),_ => candidates(rest,directory,candidateIssues(all)))(Unit{})
def loadContextFileFromDir(directory: String) -> IO(Candidate):
  candidates("AGENTS.override.md" <> "AGENTS.md" <> "AGENTS.MD" <> "CLAUDE.md" <> "CLAUDE.MD" <> Nil{},directory,Nil{})
def canonicalResult(value: Result<&2,&2,FS.Error,String>,fallback: String) -> String:
  match value:
    case Done{path}: path
    case Fail{_}: fallback
def canonicalize(+path: String) -> IO(String):
  do IO<String>:
    value : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
    return canonicalResult(value,path)
def lastPart(parts: List<&2,String>,last: String) -> String:
  match parts:
    case Nil{}: last
    case "" <> rest: lastPart(rest,last)
    case first <> rest: lastPart(rest,first)
type Shadow is Data:
  Shadow{path: Maybe<&2,String>,diagnostics: List<&2,D.ResourceDiagnostic>}
def shadowCandidate(value: Candidate,mainRoot: String) -> Shadow:
  match value:
    case Candidate{None{},issues}: Shadow{None{},issues}
    case Candidate{Some{Prompt.ContextFile{path,_}},issues}: Shadow{Some{Path.join(mainRoot,lastPart(Strings.split(path,'/'),""))},issues}
def shadowRoot(sameRepo: Bool,worktree: String,mainRoot: String) -> IO(Shadow):
  match sameRepo:
    case False{}: IO.pure(Shadow,Shadow{None{},Nil{}})
    case True{}:
      do IO<Shadow>:
        value : Candidate <- loadContextFileFromDir(worktree)
        return shadowCandidate(value,mainRoot)
def shadowNested(nested: Bool,+common: String,+worktree: String,+mainRoot: String) -> IO(Shadow):
  match nested:
    case False{}: IO.pure(Shadow,Shadow{None{},Nil{}})
    case True{}:
      do IO<Shadow>:
        mainGit : String <- canonicalize(Path.join(mainRoot,".git"))
        shadowRoot(Strings.equal(mainGit,common),worktree,mainRoot)
def shadowPaths(paths: Maybe<&2,Git.GitPaths>) -> IO(Shadow):
  match paths:
    case None{}: IO.pure(Shadow,Shadow{None{},Nil{}})
    case Some{Git.GitPaths{repo,common,_}}:
      do IO<Shadow>:
        +common : String <- canonicalize(common)
        +worktree : String <- canonicalize(repo)
        +mainRoot : String = Git.parent(common)
        shadowNested(String.starts_with(worktree,mainRoot ++ "/"),common,worktree,mainRoot)
def findShadowedContextFile(cwd: String) -> IO(Shadow):
  do IO<Shadow>:
    paths : Maybe<&2,Git.GitPaths> <- Git.findGitPaths(cwd)
    shadowPaths(paths)

# Deduplication uses the reported lexical path, as upstream does. Canonical
# paths are used only to identify a nested worktree's same-filename shadow.
type Accumulator is Data:
  Accumulator{files: List<&2,Prompt.ContextFile>,seen: Strings.StringSet,diagnostics: List<&2,D.ResourceDiagnostic>}
def filePath(value: Prompt.ContextFile) -> String:
  match value:
    case Prompt.ContextFile{path,_}: path
def include(file: Maybe<&2,Prompt.ContextFile>,issues: List<&2,D.ResourceDiagnostic>,shadowed: Bool,state: Accumulator) -> Accumulator:
  match file state:
    case None{} Accumulator{files,seen,earlier}: Accumulator{files,seen,List.append(&2,D.ResourceDiagnostic,earlier,issues)}
    case Some{+file} Accumulator{+files,+seen,earlier}:
      +path = filePath(file)
      +skip = shadowed || Strings.contains(seen,path)
      Accumulator{Bool.pick(List<&2,Prompt.ContextFile>,skip,files,file <> files),Bool.pick(Strings.StringSet,skip,seen,Strings.insert(seen,path)),List.append(&2,D.ResourceDiagnostic,earlier,issues)}
def isShadow(file: Maybe<&2,Prompt.ContextFile>,shadow: Maybe<&2,String>) -> IO(Bool):
  match file shadow:
    case Some{Prompt.ContextFile{path,_}} Some{target}:
      do IO<Bool>:
        real : String <- canonicalize(path)
        return Strings.equal(real,target)
    case _ _: IO.pure(Bool,False{})
def collected(value: Candidate,shadowed: Bool,state: Accumulator) -> Accumulator:
  match value:
    case Candidate{file,issues}: include(file,issues,shadowed,state)
def candidateFile(value: Candidate) -> Maybe<&2,Prompt.ContextFile>:
  match value:
    case Candidate{file,_}: file
@unsafe def ancestors(+directory: String,+shadow: Maybe<&2,String>,state: Accumulator) -> IO(Accumulator):
  do IO<Accumulator>:
    +value : Candidate <- loadContextFileFromDir(directory)
    skip : Bool <- isShadow(candidateFile(value),shadow)
    +next : String = Git.parent(directory)
    +nextState : Accumulator = collected(value,skip,state)
    Bool.pick(Unit -> IO(Accumulator),Strings.equal(directory,next),_ => IO.pure(Accumulator,nextState),_ => ancestors(next,shadow,nextState))(Unit{})
def finished(global: List<&2,Prompt.ContextFile>,state: Accumulator) -> ContextFiles:
  match state:
    case Accumulator{files,_,issues}: ContextFiles{List.append(&2,Prompt.ContextFile,global,files),issues}
def inherited(global: Accumulator,shadow: Shadow,cwd: String) -> IO(ContextFiles):
  match global shadow:
    case Accumulator{files,seen,issues} Shadow{path,more}:
      do IO<ContextFiles>:
        result : Accumulator <- ancestors(cwd,path,Accumulator{Nil{},seen,List.append(&2,D.ResourceDiagnostic,issues,more)})
        return finished(files,result)
def locations(cwd: Result<&2,&2,Paths.Error,String>,agentDir: Result<&2,&2,Paths.Error,String>) -> IO(ContextFiles):
  match cwd agentDir:
    case Fail{_} _: IO.pure(ContextFiles,ContextFiles{Nil{},D.warning("Invalid context working directory","") <> Nil{}})
    case _ Fail{_}: IO.pure(ContextFiles,ContextFiles{Nil{},D.warning("Invalid context agent directory","") <> Nil{}})
    case Done{+cwd} Done{agentDir}:
      do IO<ContextFiles>:
        global : Candidate <- loadContextFileFromDir(agentDir)
        shadow : Shadow <- findShadowedContextFile(cwd)
        inherited(collected(global,False{},Accumulator{Nil{},Strings.empty(),Nil{}}),shadow,cwd)
def loadProjectContextFiles(+environment: Paths.Environment,options: Options) -> IO(ContextFiles):
  match options:
    case Options{cwd,agentDir}: locations(Paths.resolvePath(environment,cwd,"",Paths.defaults()),Paths.resolvePath(environment,agentDir,"",Paths.defaults()))

# Resource discovery (upstream DefaultResourceLoader's skill and prompt
# passes)
# ----------------------------------------------------------------------

def canonicalPath(+path: String) -> IO(String):
  do IO<String>:
    real : Result<&2, &2, FS.Error, String> <- FS.realpath(path)
    return Result.default(&2, &2, FS.Error, String, real, path)

def seenPath(seen: List<&2, String>, +path: String) -> Bool:
  match seen:
    case Nil{}: False{}
    case first <> rest: String.eq(first, path) || seenPath(rest, path)

def mergedFrom(+environment: Paths.Environment, +cwd: String, paths: List<&2, String>, +seen: List<&2, String>) -> IO(List<&2, String>):
  match paths:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +path <> +rest:
      +resolved = Result.default(&2, &2, Paths.Error, String, Paths.resolvePath(environment, path, cwd, Paths.PathInputOptions{True{}, True{}, None{}, False{}, False{}}), path)
      do IO<List<&2, String>>:
        +real : String <- canonicalPath(resolved)
        Bool.pick(Unit -> IO(List<&2, String>), seenPath(seen, real),
          _ => mergedFrom(environment, cwd, rest, seen),
          _ => do IO<List<&2, String>>:
            later : List<&2, String> <- mergedFrom(environment, cwd, rest, real <> seen)
            return resolved <> later)(Unit{})

def loadedSkills(result: Skills.LoadSkillsResult) -> List<&2, Skills.Skill>:
  match result:
    case Skills.LoadSkillsResult{skills, _}: skills

def skillsFrom(+environment: Paths.Environment, +cwd: String, agentDir: String, noSkills: Bool, paths: List<&2, String>) -> IO(List<&2, Skills.Skill>):
  match noSkills paths:
    case True{} Nil{}: IO.pure(List<&2, Skills.Skill>, Nil{})
    case _ _:
      do IO<List<&2, Skills.Skill>>:
        result : Skills.LoadSkillsResult <- Skills.loadSkills(environment, Skills.LoadSkillsOptions{cwd, agentDir, paths, False{}})
        return loadedSkills(result)

def resolvedSkills(resolved: PackageManager.ResolvedPaths) -> List<&2, String>:
  match resolved:
    case PackageManager.ResolvedPaths{skills, _, _}: PackageManager.enabledPaths(skills)

def skillSourceName(source: PackageManager.Source) -> String:
  match source:
    case PackageManager.Local{}: "local"
    case PackageManager.Auto{}: "auto"

def skillScope(scope: PackageManager.Scope) -> Skills.SourceScope:
  match scope:
    case PackageManager.ProjectScope{}: Skills.Project{}
    case PackageManager.UserScope{}: Skills.User{}

# upstream metadataByPath: every resolved resource's metadata, first path wins.
def resolvedResources(resolved: PackageManager.ResolvedPaths) -> List<&2, PackageManager.ResolvedResource>:
  match resolved:
    case PackageManager.ResolvedPaths{skills, prompts, themes}: List.append(&2, PackageManager.ResolvedResource, skills, List.append(&2, PackageManager.ResolvedResource, prompts, themes))

def resourceSource(metadata: PackageManager.PathMetadata, path: String) -> Skills.SourceInfo:
  match metadata:
    case PackageManager.PathMetadata{source, scope, baseDir}:
      Skills.SourceInfo{path, skillSourceName(source), skillScope(scope), Skills.TopLevel{}, baseDir}

# upstream findSourceInfoForPath: the resource at or above the path.
def findSourceInfoForPath(+path: String, resources: List<&2, PackageManager.ResolvedResource>) -> Maybe<&2, Skills.SourceInfo>:
  match resources:
    case Nil{}: None{}
    case PackageManager.ResolvedResource{root, _, metadata} <> rest:
      Bool.pick(Maybe<&2, Skills.SourceInfo>, Skills.under(path, root), Some{resourceSource(metadata, path)}, findSourceInfoForPath(path, rest))

def sourcedSkills(skills: List<&2, Skills.Skill>, +resources: List<&2, PackageManager.ResolvedResource>) -> List<&2, Skills.Skill>:
  match skills:
    case Nil{}: Nil{}
    case Skills.Skill{name, description, +path, baseDir, source, disabled} <> rest:
      +resolved = Maybe.default(&2, Skills.SourceInfo, findSourceInfoForPath(path, resources), source)
      Skills.Skill{name, description, path, baseDir, resolved, disabled} <> sourcedSkills(rest, resources)

def sourcedTemplates(templates: List<&2, Templates.PromptTemplate>, +resources: List<&2, PackageManager.ResolvedResource>) -> List<&2, Templates.PromptTemplate>:
  match templates:
    case Nil{}: Nil{}
    case Templates.PromptTemplate{name, description, hint, content, source, +file} <> rest:
      +resolved = Maybe.default(&2, Skills.SourceInfo, findSourceInfoForPath(file, resources), source)
      Templates.PromptTemplate{name, description, hint, content, resolved, file} <> sourcedTemplates(rest, resources)

def nonLocalPrefix(+value: String) -> Bool:
  String.starts_with(value, "npm:") || String.starts_with(value, "git:") || String.starts_with(value, "github:") || String.starts_with(value, "http:") || String.starts_with(value, "https:") || String.starts_with(value, "ssh:")

# upstream isLocalPath.
def isLocalPath(value: String) -> Bool: Bool.not(nonLocalPrefix(Text.trim(value)))

def processCwd(environment: Paths.Environment) -> String:
  match environment:
    case Paths.Environment{cwd, _, _}: cwd

# upstream resolveCliPaths: local command-line paths against the process cwd.
def cliPaths(+environment: Paths.Environment, paths: List<&2, String>) -> List<&2, String>:
  match paths:
    case Nil{}: Nil{}
    case +path <> rest:
      Bool.pick(String, isLocalPath(path), Result.default(&2, &2, Paths.Error, String, Paths.resolvePath(environment, path, processCwd(environment), Paths.defaults()), path), path) <> cliPaths(environment, rest)


def resolvedPrompts(resolved: PackageManager.ResolvedPaths) -> List<&2, String>:
  match resolved:
    case PackageManager.ResolvedPaths{_, prompts, _}: PackageManager.enabledPaths(prompts)

def templateNamed(templates: List<&2, Templates.PromptTemplate>, +name: String) -> Bool:
  match templates:
    case Nil{}: False{}
    case Templates.PromptTemplate{known, _, _, _, _, _} <> rest: String.eq(known, name) || templateNamed(rest, name)

# upstream dedupePrompts: the first template of each name wins.
def dedupedTemplates(templates: List<&2, Templates.PromptTemplate>, +kept: List<&2, Templates.PromptTemplate>) -> List<&2, Templates.PromptTemplate>:
  match templates:
    case Nil{}: List.reverse(&2, Templates.PromptTemplate, kept)
    case Templates.PromptTemplate{+name, description, hint, content, source, file} <> +rest:
      Bool.pick(Unit -> List<&2, Templates.PromptTemplate>, templateNamed(kept, name),
        _ => dedupedTemplates(rest, kept),
        _ => dedupedTemplates(rest, Templates.PromptTemplate{name, description, hint, content, source, file} <> kept))(Unit{})

def loadedTemplates(result: Result<&2, &2, Paths.Error, Templates.LoadResult>) -> List<&2, Templates.PromptTemplate>:
  match result:
    case Fail{_}: Nil{}
    case Done{Templates.LoadResult{templates, _}}: dedupedTemplates(templates, Nil{})

def templatesFrom(+environment: Paths.Environment, +cwd: String, agentDir: String, noTemplates: Bool, paths: List<&2, String>) -> IO(List<&2, Templates.PromptTemplate>):
  match noTemplates paths:
    case True{} Nil{}: IO.pure(List<&2, Templates.PromptTemplate>, Nil{})
    case _ _:
      do IO<List<&2, Templates.PromptTemplate>>:
        result : Result<&2, &2, Paths.Error, Templates.LoadResult> <- Templates.loadPromptTemplates(environment, ".pi", Templates.LoadPromptTemplatesOptions{cwd, agentDir, paths, False{}})
        return loadedTemplates(result)

# The skills of the package manager's enabled resources (unless noSkills)
# and the additional paths (resolved against the process cwd), deduplicated
# by canonical path and loaded without the default directories, with the
# package metadata of their resource.
type SkillsResult is Data:
  SkillsResult{skills: List<&2, Skills.Skill>, diagnostics: List<&2, D.ResourceDiagnostic>}

def skillsOf(result: SkillsResult) -> List<&2, Skills.Skill>:
  match result:
    case SkillsResult{skills, _}: skills

def skillResult(+resources: List<&2, PackageManager.ResolvedResource>, result: Skills.LoadSkillsResult) -> SkillsResult:
  match result:
    case Skills.LoadSkillsResult{skills, diagnostics}: SkillsResult{sourcedSkills(skills, resources), diagnostics}

def skillsFromPaths(+environment: Paths.Environment, +cwd: String, agentDir: String, noSkills: Bool, paths: List<&2, String>) -> IO(Skills.LoadSkillsResult):
  match noSkills paths:
    case True{} Nil{}: IO.pure(Skills.LoadSkillsResult, Skills.emptyResult())
    case _ _: Skills.loadSkills(environment, Skills.LoadSkillsOptions{cwd, agentDir, paths, False{}})

def loadSkillResources(+environment: Paths.Environment, +cwd: String, +agentDir: String, +noSkills: Bool, additional: List<&2, String>, +resolved: PackageManager.ResolvedPaths) -> IO(SkillsResult):
  do IO<SkillsResult>:
    merged : List<&2, String> <- mergedFrom(environment, cwd, List.append(&2, String, Bool.pick(List<&2, String>, noSkills, Nil{}, resolvedSkills(resolved)), cliPaths(environment, additional)), Nil{})
    loaded : Skills.LoadSkillsResult <- skillsFromPaths(environment, cwd, agentDir, noSkills, merged)
    return skillResult(resolvedResources(resolved), loaded)

# The prompt templates likewise; the first template of each name wins.
type PromptsResult is Data:
  PromptsResult{prompts: List<&2, Templates.PromptTemplate>, diagnostics: List<&2, D.ResourceDiagnostic>}

def promptsOf(result: PromptsResult) -> List<&2, Templates.PromptTemplate>:
  match result:
    case PromptsResult{prompts, _}: prompts

def promptResultOf(+resources: List<&2, PackageManager.ResolvedResource>, result: Result<&2, &2, Paths.Error, Templates.LoadResult>) -> PromptsResult:
  match result:
    case Fail{_}: PromptsResult{Nil{}, Nil{}}
    case Done{Templates.LoadResult{templates, diagnostics}}: PromptsResult{sourcedTemplates(dedupedTemplates(templates, Nil{}), resources), diagnostics}

def templatesFromPaths(+environment: Paths.Environment, +cwd: String, agentDir: String, noTemplates: Bool, paths: List<&2, String>) -> IO(Result<&2, &2, Paths.Error, Templates.LoadResult>):
  match noTemplates paths:
    case True{} Nil{}: IO.pure(Result<&2, &2, Paths.Error, Templates.LoadResult>, Done{Templates.LoadResult{Nil{}, Nil{}}})
    case _ _: Templates.loadPromptTemplates(environment, ".pi", Templates.LoadPromptTemplatesOptions{cwd, agentDir, paths, False{}})

def loadPromptResources(+environment: Paths.Environment, +cwd: String, +agentDir: String, +noTemplates: Bool, additional: List<&2, String>, +resolved: PackageManager.ResolvedPaths) -> IO(PromptsResult):
  do IO<PromptsResult>:
    merged : List<&2, String> <- mergedFrom(environment, cwd, List.append(&2, String, Bool.pick(List<&2, String>, noTemplates, Nil{}, resolvedPrompts(resolved)), cliPaths(environment, additional)), Nil{})
    loaded : Result<&2, &2, Paths.Error, Templates.LoadResult> <- templatesFromPaths(environment, cwd, agentDir, noTemplates, merged)
    return promptResultOf(resolvedResources(resolved), loaded)

# Themes (upstream loadThemes without the default directories: the package
# manager already resolves them)
# ------------------------------------------------------------------------

type ThemesResult is Data:
  ThemesResult{themes: List<&2, Theme.Theme>, diagnostics: List<&2, D.ResourceDiagnostic>}

def themeError(error: Theme.LoadError) -> String:
  match error:
    case Theme.Read{cause}: systemMessage(cause)
    case Theme.Decode{_}: "Invalid UTF-8 in theme file"
    case Theme.Invalid{_}: "failed to load theme"
    case Theme.NotFound{name}: "Theme not found: " ++ name

def withTheme(+path: String, result: Result<&2, &2, Theme.LoadError, Theme.Theme>, loaded: ThemesResult) -> ThemesResult:
  match result loaded:
    case Done{theme} ThemesResult{themes, issues}: ThemesResult{List.append(&2, Theme.Theme, themes, [theme]), issues}
    case Fail{error} ThemesResult{themes, issues}: ThemesResult{themes, List.append(&2, D.ResourceDiagnostic, issues, [D.warning(themeError(error), path)])}

def jsonName(+name: String) -> Bool: String.ends_with(name, ".json")

def themeFiles(entries: List<&2, FS.DirectoryEntry>, +dir: String) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case FS.DirectoryEntry{+name, FS.RegularFile{}} <> +rest: Bool.pick(List<&2, String>, jsonName(name), Path.join(dir, name) <> themeFiles(rest, dir), themeFiles(rest, dir))
    case _ <> rest: themeFiles(rest, dir)

def themesFromFiles(files: List<&2, String>, +mode: Color.Mode, loaded: ThemesResult) -> IO(ThemesResult):
  match files:
    case Nil{}: IO.pure(ThemesResult, loaded)
    case +file <> rest:
      do IO<ThemesResult>:
        result : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadFromPath(file, mode)
        themesFromFiles(rest, mode, withTheme(file, result, loaded))

def themesInDirectory(listed: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>, +dir: String, +mode: Color.Mode, loaded: ThemesResult) -> IO(ThemesResult):
  match listed loaded:
    case Done{entries} _: themesFromFiles(themeFiles(entries, dir), mode, loaded)
    case Fail{error} ThemesResult{themes, issues}: IO.pure(ThemesResult, ThemesResult{themes, List.append(&2, D.ResourceDiagnostic, issues, [D.warning(systemMessage(error), dir)])})

def themesAt(kind: Result<&2, &2, FS.Error, FS.FileKind>, +path: String, +mode: Color.Mode, loaded: ThemesResult) -> IO(ThemesResult):
  match kind loaded:
    case Done{FS.Directory{}} _:
      do IO<ThemesResult>:
        listed : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(path)
        themesInDirectory(listed, path, mode, loaded)
    case Done{FS.RegularFile{}} ThemesResult{+themes, +issues}: Bool.pick(Unit -> IO(ThemesResult), jsonName(path), _ => themesFromFiles([path], mode, ThemesResult{themes, issues}), _ => IO.pure(ThemesResult, ThemesResult{themes, List.append(&2, D.ResourceDiagnostic, issues, [D.warning("theme path is not a json file", path)])}))(Unit{})
    case Fail{FS.System{2, _}} ThemesResult{themes, issues}: IO.pure(ThemesResult, ThemesResult{themes, List.append(&2, D.ResourceDiagnostic, issues, [D.warning("theme path does not exist", path)])})
    case _ ThemesResult{themes, issues}: IO.pure(ThemesResult, ThemesResult{themes, List.append(&2, D.ResourceDiagnostic, issues, [D.warning("theme path is not a json file", path)])})

def themesFromPaths(paths: List<&2, String>, +mode: Color.Mode, loaded: ThemesResult) -> IO(ThemesResult):
  match paths:
    case Nil{}: IO.pure(ThemesResult, loaded)
    case +path <> rest:
      do IO<ThemesResult>:
        kind : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind(path)
        next : ThemesResult <- themesAt(kind, path, mode, loaded)
        themesFromPaths(rest, mode, next)

def themeNamed(themes: List<&2, Theme.Theme>, +name: String) -> Bool:
  match themes:
    case Nil{}: False{}
    case Theme.Theme{known, _, _, _, _, _} <> rest: String.eq(known, name) || themeNamed(rest, name)

# upstream dedupeThemes: the first theme of each name wins.
def dedupedThemes(themes: List<&2, Theme.Theme>, +kept: List<&2, Theme.Theme>) -> List<&2, Theme.Theme>:
  match themes:
    case Nil{}: kept
    case Theme.Theme{+name, mode, fg, bg, fgAnsi, bgAnsi} <> rest: dedupedThemes(rest, Bool.pick(List<&2, Theme.Theme>, themeNamed(kept, name), kept, List.append(&2, Theme.Theme, kept, [Theme.Theme{name, mode, fg, bg, fgAnsi, bgAnsi}])))

def resolvedThemes(resolved: PackageManager.ResolvedPaths) -> List<&2, String>:
  match resolved:
    case PackageManager.ResolvedPaths{_, _, themes}: PackageManager.enabledPaths(themes)

def dedupedResult(result: ThemesResult) -> ThemesResult:
  match result:
    case ThemesResult{themes, issues}: ThemesResult{dedupedThemes(themes, Nil{}), issues}

def themesLoaded(paths: List<&2, String>, +mode: Color.Mode) -> IO(ThemesResult):
  do IO<ThemesResult>:
    loaded : ThemesResult <- themesFromPaths(paths, mode, ThemesResult{Nil{}, Nil{}})
    return dedupedResult(loaded)

def loadThemeResources(+environment: Paths.Environment, +noThemes: Bool, additional: List<&2, String>, +mode: Color.Mode, resolved: PackageManager.ResolvedPaths) -> IO(ThemesResult):
  +paths = List.append(&2, String, Bool.pick(List<&2, String>, noThemes, Nil{}, resolvedThemes(resolved)), cliPaths(environment, additional))
  Bool.pick(Unit -> IO(ThemesResult), noThemes && List.is_empty(&2, String, paths), _ => IO.pure(ThemesResult, ThemesResult{Nil{}, Nil{}}), _ => themesLoaded(paths, mode))(Unit{})

# System prompt files (upstream discoverSystemPromptFile and
# discoverAppendSystemPromptFile): a trusted project's .pi file, else the
# agent directory's.
# -----------------------------------------------------------------------

def existing(+path: String) -> IO(Bool):
  do IO<Bool>:
    kind : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind(path)
    return Result.is_done(&2, &2, FS.Error, FS.FileKind, kind)

def discoveredPromptFile(+cwd: String, +agentDir: String, +trusted: Bool, +name: String) -> IO(Maybe<&2, String>):
  +project = Path.join(Path.join(cwd, ".pi"), name)
  +global = Path.join(agentDir, name)
  do IO<Maybe<&2, String>>:
    projectFound : Bool <- existing(project)
    globalFound : Bool <- existing(global)
    return Bool.pick(Maybe<&2, String>, trusted && projectFound, Some{project}, Bool.pick(Maybe<&2, String>, globalFound, Some{global}, None{}))

def fileText(result: Result<&2, &2, FS.Error, List<&2, U32>>, +fallback: String) -> String:
  match result:
    case Done{bytes}: stripBom(Result.default(&2, &2, Utf8.Error, String, Utf8.decodeWith(Utf8.Preserve{}, bytes), fallback))
    case Fail{_}: fallback

def fileRead(+text: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(text)
    return Some{fileText(bytes, text)}

# upstream resolvePromptInput: a file's content when the input names an
# existing file, else the input itself.
def resolvePromptInput(input: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match input:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{SNil{}}: IO.pure(Maybe<&2, String>, None{})
    case Some{+text}:
      do IO<Maybe<&2, String>>:
        found : Bool <- existing(text)
        Bool.pick(Unit -> IO(Maybe<&2, String>), found, _ => fileRead(text), _ => IO.pure(Maybe<&2, String>, Some{text}))(Unit{})

def existingSource(input: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match input:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{+path}:
      do IO<Maybe<&2, String>>:
        found : Bool <- existing(path)
        return Bool.pick(Maybe<&2, String>, found, Some{path}, None{})

def prependFound(text: Maybe<&2, String>, others: List<&2, String>) -> List<&2, String>:
  match text:
    case None{}: others
    case Some{found}: found <> others

def resolvedInputs(inputs: List<&2, String>) -> IO(List<&2, String>):
  match inputs:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case input <> rest:
      do IO<List<&2, String>>:
        text : Maybe<&2, String> <- resolvePromptInput(Some{input})
        others : List<&2, String> <- resolvedInputs(rest)
        return prependFound(text, others)

type SourcePath is Data:
  SourcePath{path: String}

def existingSources(inputs: List<&2, String>) -> IO(List<&2, SourcePath>):
  match inputs:
    case Nil{}: IO.pure(List<&2, SourcePath>, Nil{})
    case +input <> rest:
      do IO<List<&2, SourcePath>>:
        found : Bool <- existing(input)
        +others : List<&2, SourcePath> <- existingSources(rest)
        return Bool.pick(List<&2, SourcePath>, found, SourcePath{input} <> others, others)

# The ResourceLoader interface
# ----------------------------

type AgentsFilesResult is Data:
  AgentsFilesResult{agentsFiles: List<&2, Prompt.ContextFile>}

def agentsFilesOf(result: AgentsFilesResult) -> List<&2, Prompt.ContextFile>:
  match result:
    case AgentsFilesResult{files}: files

# upstream LoadExtensionsResult: the loaded extensions, their load errors and
# the runtime they registered through.
type LoadExtensionsResult is Data:
  LoadExtensionsResult{extensions: List<&2, ExtensionTypes.Extension>, errors: List<&2, ExtensionTypes.LoadError>, runtime: ExtensionTypes.ExtensionRuntime()}

# upstream ResourceExtensionPaths (resources_discover results).
type ResourceExtensionPaths is Data:
  ResourceExtensionPaths{skillPaths: List<&2, String>, promptPaths: List<&2, String>, themePaths: List<&2, String>}

# upstream ResourceLoaderReloadOptions. Native settings are values the
# session holds, so a reload is given the settings to reload under (None
# keeps the loader's); resolveProjectTrust is not ported.
type ResourceLoaderReloadOptions is Data:
  ResourceLoaderReloadOptions{settings: Maybe<&2, Settings.SettingsManager>}

# upstream ResourceLoader: an injectable interface, one callback per method.
type ResourceLoader is Data:
  ResourceLoader{getExtensions: C.Callback<Unit, LoadExtensionsResult>, getSkills: C.Callback<Unit, SkillsResult>, getPrompts: C.Callback<Unit, PromptsResult>, getThemes: C.Callback<Unit, ThemesResult>, getAgentsFiles: C.Callback<Unit, AgentsFilesResult>, getSystemPrompt: C.Callback<Unit, Maybe<&2, String>>, getSystemPromptSource: C.Callback<Unit, Maybe<&2, SourcePath>>, getAppendSystemPrompt: C.Callback<Unit, List<&2, String>>, getAppendSystemPromptSources: C.Callback<Unit, List<&2, SourcePath>>, extendResources: C.Callback<ResourceExtensionPaths, Unit>, reload: C.Callback<ResourceLoaderReloadOptions, Unit>}

def getExtensions(loader: ResourceLoader) -> IO(LoadExtensionsResult):
  match loader:
    case ResourceLoader{get, _, _, _, _, _, _, _, _, _, _}: C.call(Unit, LoadExtensionsResult, get, Unit{})

def getSkills(loader: ResourceLoader) -> IO(SkillsResult):
  match loader:
    case ResourceLoader{_, get, _, _, _, _, _, _, _, _, _}: C.call(Unit, SkillsResult, get, Unit{})

def getPrompts(loader: ResourceLoader) -> IO(PromptsResult):
  match loader:
    case ResourceLoader{_, _, get, _, _, _, _, _, _, _, _}: C.call(Unit, PromptsResult, get, Unit{})

def getThemes(loader: ResourceLoader) -> IO(ThemesResult):
  match loader:
    case ResourceLoader{_, _, _, get, _, _, _, _, _, _, _}: C.call(Unit, ThemesResult, get, Unit{})

def getAgentsFiles(loader: ResourceLoader) -> IO(AgentsFilesResult):
  match loader:
    case ResourceLoader{_, _, _, _, get, _, _, _, _, _, _}: C.call(Unit, AgentsFilesResult, get, Unit{})

def getSystemPrompt(loader: ResourceLoader) -> IO(Maybe<&2, String>):
  match loader:
    case ResourceLoader{_, _, _, _, _, get, _, _, _, _, _}: C.call(Unit, Maybe<&2, String>, get, Unit{})

def getSystemPromptSource(loader: ResourceLoader) -> IO(Maybe<&2, SourcePath>):
  match loader:
    case ResourceLoader{_, _, _, _, _, _, get, _, _, _, _}: C.call(Unit, Maybe<&2, SourcePath>, get, Unit{})

def getAppendSystemPrompt(loader: ResourceLoader) -> IO(List<&2, String>):
  match loader:
    case ResourceLoader{_, _, _, _, _, _, _, get, _, _, _}: C.call(Unit, List<&2, String>, get, Unit{})

def getAppendSystemPromptSources(loader: ResourceLoader) -> IO(List<&2, SourcePath>):
  match loader:
    case ResourceLoader{_, _, _, _, _, _, _, _, get, _, _}: C.call(Unit, List<&2, SourcePath>, get, Unit{})

def extendResources(loader: ResourceLoader, paths: ResourceExtensionPaths) -> IO(Unit):
  match loader:
    case ResourceLoader{_, _, _, _, _, _, _, _, _, extend, _}: C.call(ResourceExtensionPaths, Unit, extend, paths)

def reload(loader: ResourceLoader, options: ResourceLoaderReloadOptions) -> IO(Unit):
  match loader:
    case ResourceLoader{_, _, _, _, _, _, _, _, _, _, again}: C.call(ResourceLoaderReloadOptions, Unit, again, options)

# Whoever created a loader's callbacks disposes them.
def disposeResourceLoader(loader: ResourceLoader) -> IO(Unit):
  match loader:
    case ResourceLoader{a, b, c, d, e, f, g, h, i, j, k}:
      do IO<Unit>:
        C.dispose(Unit, LoadExtensionsResult, a)
        C.dispose(Unit, SkillsResult, b)
        C.dispose(Unit, PromptsResult, c)
        C.dispose(Unit, ThemesResult, d)
        C.dispose(Unit, AgentsFilesResult, e)
        C.dispose(Unit, Maybe<&2, String>, f)
        C.dispose(Unit, Maybe<&2, SourcePath>, g)
        C.dispose(Unit, List<&2, String>, h)
        C.dispose(Unit, List<&2, SourcePath>, i)
        C.dispose(ResourceExtensionPaths, Unit, j)
        C.dispose(ResourceLoaderReloadOptions, Unit, k)

# DefaultResourceLoader
# ---------------------

# upstream DefaultResourceLoaderOptions without the event bus, extension
# paths (JavaScript extensions are excluded) and the override hooks.
# `extensionFactories` load when the loader is created: they are Bend
# closures, consumed by loading, so a reload keeps the extensions loaded
# then (upstream's reload runs the factories again).
type DefaultResourceLoaderOptions is Data:
  DefaultResourceLoaderOptions{cwd: String, agentDir: String, settingsManager: Settings.SettingsManager, additionalSkillPaths: List<&2, String>, additionalPromptTemplatePaths: List<&2, String>, additionalThemePaths: List<&2, String>, noExtensions: Bool, noSkills: Bool, noPromptTemplates: Bool, noThemes: Bool, noContextFiles: Bool, systemPrompt: Maybe<&2, String>, appendSystemPrompt: Maybe<&2, List<&2, String>>}

def defaultResourceLoaderOptions(cwd: String, agentDir: String, settings: Settings.SettingsManager) -> DefaultResourceLoaderOptions:
  DefaultResourceLoaderOptions{cwd, agentDir, settings, Nil{}, Nil{}, Nil{}, False{}, False{}, False{}, False{}, False{}, None{}, None{}}

# What the last reload found (upstream's instance fields).
type Loaded is Data:
  Loaded{skills: SkillsResult, prompts: PromptsResult, themes: ThemesResult, agentsFiles: AgentsFilesResult, systemPrompt: Maybe<&2, String>, systemPromptSource: Maybe<&2, SourcePath>, appendSystemPrompt: List<&2, String>, appendSystemPromptSources: List<&2, SourcePath>, extensionPaths: ResourceExtensionPaths}

def emptyLoaded() -> Loaded:
  Loaded{SkillsResult{Nil{}, Nil{}}, PromptsResult{Nil{}, Nil{}}, ThemesResult{Nil{}, Nil{}}, AgentsFilesResult{Nil{}}, None{}, None{}, Nil{}, Nil{}, ResourceExtensionPaths{Nil{}, Nil{}, Nil{}}}

type LoaderState is Data:
  LoaderState{environment: Paths.Environment, options: DefaultResourceLoaderOptions, extensions: LoadExtensionsResult, loaded: Loaded, mode: Color.Mode}

def withSettingsOption(options: DefaultResourceLoaderOptions, settings: Maybe<&2, Settings.SettingsManager>) -> DefaultResourceLoaderOptions:
  match options settings:
    case options None{}: options
    case DefaultResourceLoaderOptions{cwd, agentDir, _, skills, prompts, themes, noExtensions, noSkills, noPrompts, noThemes, noContext, system, append} Some{chosen}:
      DefaultResourceLoaderOptions{cwd, agentDir, chosen, skills, prompts, themes, noExtensions, noSkills, noPrompts, noThemes, noContext, system, append}

def contextFilesOf(found: ContextFiles) -> List<&2, Prompt.ContextFile>:
  match found:
    case ContextFiles{files, _}: files

def contextFilesResult(noContextFiles: Bool, +environment: Paths.Environment, +cwd: String, +agentDir: String) -> IO(AgentsFilesResult):
  match noContextFiles:
    case True{}: IO.pure(AgentsFilesResult, AgentsFilesResult{Nil{}})
    case False{}:
      do IO<AgentsFilesResult>:
        found : ContextFiles <- loadProjectContextFiles(environment, Options{cwd, agentDir})
        return AgentsFilesResult{contextFilesOf(found)}

def appendSourcesFor(configured: Maybe<&2, List<&2, String>>, discovered: Maybe<&2, String>) -> List<&2, String>:
  match configured:
    case Some{sources}: sources
    case None{}: Maybe.default(&2, List<&2, String>, Maybe.map(&2, String, List<&2, String>, found => [found], discovered), Nil{})

# upstream reload(): package resolution, then skills, prompts, themes,
# context files and the system prompt pieces. Extension resource paths added
# by extendResources join the skill, prompt and theme paths.
def reloaded(+environment: Paths.Environment, options: DefaultResourceLoaderOptions, +extra: ResourceExtensionPaths, +mode: Color.Mode) -> IO(Loaded):
  match options extra:
    case DefaultResourceLoaderOptions{+cwd, +agentDir, +settings, skillPaths, promptPaths, themePaths, _, noSkills, noPrompts, noThemes, noContext, systemPrompt, appendSystemPrompt} ResourceExtensionPaths{extraSkills, extraPrompts, extraThemes}:
      do IO<Loaded>:
        +resolved : PackageManager.ResolvedPaths <- PackageManager.resolve(environment, settings, cwd, agentDir)
        skills : SkillsResult <- loadSkillResources(environment, cwd, agentDir, noSkills, List.append(&2, String, skillPaths, extraSkills), resolved)
        prompts : PromptsResult <- loadPromptResources(environment, cwd, agentDir, noPrompts, List.append(&2, String, promptPaths, extraPrompts), resolved)
        themes : ThemesResult <- loadThemeResources(environment, noThemes, List.append(&2, String, themePaths, extraThemes), mode, resolved)
        agentsFiles : AgentsFilesResult <- contextFilesResult(noContext, environment, cwd, agentDir)
        +trusted : Bool = Settings.isProjectTrusted(settings)
        discoveredSystem : Maybe<&2, String> <- discoveredPromptFile(cwd, agentDir, trusted, "SYSTEM.md")
        +systemSource : Maybe<&2, String> = Maybe.or(&2, String, systemPrompt, discoveredSystem)
        system : Maybe<&2, String> <- resolvePromptInput(systemSource)
        systemFile : Maybe<&2, String> <- existingSource(systemSource)
        discoveredAppend : Maybe<&2, String> <- discoveredPromptFile(cwd, agentDir, trusted, "APPEND_SYSTEM.md")
        +appendSources : List<&2, String> = appendSourcesFor(appendSystemPrompt, discoveredAppend)
        append : List<&2, String> <- resolvedInputs(appendSources)
        appendFiles : List<&2, SourcePath> <- existingSources(appendSources)
        return Loaded{skills, prompts, themes, agentsFiles, system, Maybe.map(&2, String, SourcePath, path => SourcePath{path}, systemFile), append, appendFiles, ResourceExtensionPaths{extraSkills, extraPrompts, extraThemes}}

def loadedOf(state: LoaderState) -> Loaded:
  match state:
    case LoaderState{_, _, _, loaded, _}: loaded

def extensionsOf(state: LoaderState) -> LoadExtensionsResult:
  match state:
    case LoaderState{_, _, extensions, _, _}: extensions

def skillsIn(loaded: Loaded) -> SkillsResult:
  match loaded:
    case Loaded{value, _, _, _, _, _, _, _, _}: value

def promptsIn(loaded: Loaded) -> PromptsResult:
  match loaded:
    case Loaded{_, value, _, _, _, _, _, _, _}: value

def themesIn(loaded: Loaded) -> ThemesResult:
  match loaded:
    case Loaded{_, _, value, _, _, _, _, _, _}: value

def agentsFilesIn(loaded: Loaded) -> AgentsFilesResult:
  match loaded:
    case Loaded{_, _, _, value, _, _, _, _, _}: value

def systemPromptIn(loaded: Loaded) -> Maybe<&2, String>:
  match loaded:
    case Loaded{_, _, _, _, value, _, _, _, _}: value

def systemPromptSourceIn(loaded: Loaded) -> Maybe<&2, SourcePath>:
  match loaded:
    case Loaded{_, _, _, _, _, value, _, _, _}: value

def appendSystemPromptIn(loaded: Loaded) -> List<&2, String>:
  match loaded:
    case Loaded{_, _, _, _, _, _, value, _, _}: value

def appendSourcesIn(loaded: Loaded) -> List<&2, SourcePath>:
  match loaded:
    case Loaded{_, _, _, _, _, _, _, value, _}: value

def readLoaded(state: R.Ref<LoaderState>) -> IO(Loaded):
  do IO<Loaded>:
    current : LoaderState <- R.read(LoaderState, state)
    return loadedOf(current)

def readWith(-A: Data, state: R.Ref<LoaderState>, get: Loaded -> A) -> IO(A):
  do IO<A>:
    loaded : Loaded <- readLoaded(state)
    return get(loaded)

def loaderExtensions(state: R.Ref<LoaderState>, unit: Unit) -> IO(LoadExtensionsResult):
  do IO<LoadExtensionsResult>:
    current : LoaderState <- R.read(LoaderState, state)
    return extensionsOf(current)

def loaderSkills(state: R.Ref<LoaderState>, unit: Unit) -> IO(SkillsResult): readWith(SkillsResult, state, skillsIn)
def loaderPrompts(state: R.Ref<LoaderState>, unit: Unit) -> IO(PromptsResult): readWith(PromptsResult, state, promptsIn)
def loaderThemes(state: R.Ref<LoaderState>, unit: Unit) -> IO(ThemesResult): readWith(ThemesResult, state, themesIn)
def loaderAgentsFiles(state: R.Ref<LoaderState>, unit: Unit) -> IO(AgentsFilesResult): readWith(AgentsFilesResult, state, agentsFilesIn)
def loaderSystemPrompt(state: R.Ref<LoaderState>, unit: Unit) -> IO(Maybe<&2, String>): readWith(Maybe<&2, String>, state, systemPromptIn)
def loaderSystemPromptSource(state: R.Ref<LoaderState>, unit: Unit) -> IO(Maybe<&2, SourcePath>): readWith(Maybe<&2, SourcePath>, state, systemPromptSourceIn)
def loaderAppendSystemPrompt(state: R.Ref<LoaderState>, unit: Unit) -> IO(List<&2, String>): readWith(List<&2, String>, state, appendSystemPromptIn)
def loaderAppendSources(state: R.Ref<LoaderState>, unit: Unit) -> IO(List<&2, SourcePath>): readWith(List<&2, SourcePath>, state, appendSourcesIn)

def extensionPathsIn(loaded: Loaded) -> ResourceExtensionPaths:
  match loaded:
    case Loaded{_, _, _, _, _, _, _, _, value}: value

def reloadFrom(+state: R.Ref<LoaderState>, settings: Maybe<&2, Settings.SettingsManager>, +extra: Maybe<&2, ResourceExtensionPaths>, current: LoaderState) -> IO(Unit):
  match current:
    case LoaderState{+environment, options, extensions, previous, +mode}:
      do IO<Unit>:
        +chosen : DefaultResourceLoaderOptions = withSettingsOption(options, settings)
        loaded : Loaded <- reloaded(environment, chosen, Maybe.default(&2, ResourceExtensionPaths, extra, extensionPathsIn(previous)), mode)
        R.write(LoaderState, state, LoaderState{environment, chosen, extensions, loaded, mode})

def reloadState(+state: R.Ref<LoaderState>, settings: Maybe<&2, Settings.SettingsManager>, +extra: Maybe<&2, ResourceExtensionPaths>) -> IO(Unit):
  do IO<Unit>:
    current : LoaderState <- R.read(LoaderState, state)
    reloadFrom(state, settings, extra, current)

# upstream reload(): extension resource paths from resources_discover start
# over (upstream resets them before its extensions discover again).
def loaderReload(state: R.Ref<LoaderState>, options: ResourceLoaderReloadOptions) -> IO(Unit):
  match options:
    case ResourceLoaderReloadOptions{settings}: reloadState(state, settings, Some{ResourceExtensionPaths{Nil{}, Nil{}, Nil{}}})

def mergedPaths(previous: ResourceExtensionPaths, added: ResourceExtensionPaths) -> ResourceExtensionPaths:
  match previous added:
    case ResourceExtensionPaths{a, b, c} ResourceExtensionPaths{x, y, z}: ResourceExtensionPaths{List.append(&2, String, a, x), List.append(&2, String, b, y), List.append(&2, String, c, z)}

# upstream extendResources(paths): the skill, prompt and theme paths join
# the loaded ones.
def extendWith(+state: R.Ref<LoaderState>, paths: ResourceExtensionPaths) -> IO(Unit):
  do IO<Unit>:
    current : LoaderState <- R.read(LoaderState, state)
    reloadState(state, None{}, Some{mergedPaths(extensionPathsIn(loadedOf(current)), paths)})

def loaderExtend(state: R.Ref<LoaderState>, paths: ResourceExtensionPaths) -> IO(Unit): extendWith(state, paths)

# upstream getCapabilities().trueColor: COLORTERM of truecolor or 24bit.
def colorMode(value: Result<&1, &1, U32 & String, String>) -> Color.Mode:
  match value:
    case Done{+name}: Color.modeFor(String.eq(name, "truecolor") || String.eq(name, "24bit"))
    case Fail{_}: Color.modeFor(False{})

type DefaultResourceLoader is Data:
  DefaultResourceLoader{state: R.Ref<LoaderState>, loader: ResourceLoader}

def loaderOf(loader: DefaultResourceLoader) -> ResourceLoader:
  match loader:
    case DefaultResourceLoader{_, value}: value

def loadedExtensions(+runtime: ExtensionTypes.ExtensionRuntime(), errors: List<&2, ExtensionTypes.LoadError>) -> IO(LoadExtensionsResult):
  do IO<LoadExtensionsResult>:
    state : ExtensionTypes.ExtensionRuntimeState <- R.read(ExtensionTypes.ExtensionRuntimeState, runtime)
    return LoadExtensionsResult{ExtensionLoader.activeExtensions(ExtensionLoader.extensionsOf(state)), errors, runtime}

# upstream new DefaultResourceLoader(options): nothing is discovered until
# reload(); the inline extension factories load now (see the options).
def createDefaultResourceLoader(+environment: Paths.Environment, options: DefaultResourceLoaderOptions, extensionFactories: List<&1, ExtensionTypes.InlineExtension>) -> IO(DefaultResourceLoader):
  do IO<DefaultResourceLoader>:
    +runtime : ExtensionTypes.ExtensionRuntime() <- ExtensionLoader.createExtensionRuntime()
    errors : List<&2, ExtensionTypes.LoadError> <- ExtensionLoader.loadExtensionFactories(runtime, extensionFactories)
    extensions : LoadExtensionsResult <- loadedExtensions(runtime, errors)
    colorTerm : Result<&1, &1, U32 & String, String> <- IO.get_env("COLORTERM")
    +state : R.Ref<LoaderState> <- R.new(LoaderState, LoaderState{environment, options, extensions, emptyLoaded(), colorMode(colorTerm)})
    a : C.Callback<Unit, LoadExtensionsResult> <- C.create(~R.Ref<LoaderState>, ~Unit, ~LoadExtensionsResult, ~loaderExtensions, state)
    b : C.Callback<Unit, SkillsResult> <- C.create(~R.Ref<LoaderState>, ~Unit, ~SkillsResult, ~loaderSkills, state)
    c : C.Callback<Unit, PromptsResult> <- C.create(~R.Ref<LoaderState>, ~Unit, ~PromptsResult, ~loaderPrompts, state)
    d : C.Callback<Unit, ThemesResult> <- C.create(~R.Ref<LoaderState>, ~Unit, ~ThemesResult, ~loaderThemes, state)
    e : C.Callback<Unit, AgentsFilesResult> <- C.create(~R.Ref<LoaderState>, ~Unit, ~AgentsFilesResult, ~loaderAgentsFiles, state)
    f : C.Callback<Unit, Maybe<&2, String>> <- C.create(~R.Ref<LoaderState>, ~Unit, ~Maybe<&2, String>, ~loaderSystemPrompt, state)
    g : C.Callback<Unit, Maybe<&2, SourcePath>> <- C.create(~R.Ref<LoaderState>, ~Unit, ~Maybe<&2, SourcePath>, ~loaderSystemPromptSource, state)
    h : C.Callback<Unit, List<&2, String>> <- C.create(~R.Ref<LoaderState>, ~Unit, ~List<&2, String>, ~loaderAppendSystemPrompt, state)
    i : C.Callback<Unit, List<&2, SourcePath>> <- C.create(~R.Ref<LoaderState>, ~Unit, ~List<&2, SourcePath>, ~loaderAppendSources, state)
    j : C.Callback<ResourceExtensionPaths, Unit> <- C.create(~R.Ref<LoaderState>, ~ResourceExtensionPaths, ~Unit, ~loaderExtend, state)
    k : C.Callback<ResourceLoaderReloadOptions, Unit> <- C.create(~R.Ref<LoaderState>, ~ResourceLoaderReloadOptions, ~Unit, ~loaderReload, state)
    return DefaultResourceLoader{state, ResourceLoader{a, b, c, d, e, f, g, h, i, j, k}}

# The loader's callbacks and state; its extension runtime goes with the
# runner the session creates for it.
def disposeDefaultResourceLoader(loader: DefaultResourceLoader) -> IO(Unit):
  match loader:
    case DefaultResourceLoader{state, callbacks}:
      do IO<Unit>:
        disposeResourceLoader(callbacks)
        previous : LoaderState <- R.dispose(LoaderState, state)
        return Unit{}
