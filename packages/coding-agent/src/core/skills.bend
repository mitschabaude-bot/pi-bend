import Base
import ./diagnostics.bend as D
import ../utils/frontmatter.bend as Frontmatter
import ../utils/paths.bend as Paths
import ../../../runtime/src/yaml.bend as Yaml
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/ignore.bend as Ignore
import ../../../runtime/src/stable-sort.bend as Sort

# Native skill resources. Loading and discovery perform explicit IO; formatting
# consumes the immutable resource values without reading the filesystem.
type SourceScope is Data:
  User{}
  Project{}
  Temporary{}
type SourceOrigin is Data:
  Package{}
  TopLevel{}
type SourceInfo is Data:
  SourceInfo{path: String,source: String,scope: SourceScope,origin: SourceOrigin,baseDir: Maybe<&2,String>}
type Skill is Data:
  Skill{name: String,description: String,filePath: String,baseDir: String,sourceInfo: SourceInfo,disableModelInvocation: Bool}
type FileReadTool is Data:
  Read{}
  Bash{}

def escapeXml(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'&',rest}: escapeXml(rest,String.reverse.go("&amp;",reversed))
    case SCon{'<',rest}: escapeXml(rest,String.reverse.go("&lt;",reversed))
    case SCon{'>',rest}: escapeXml(rest,String.reverse.go("&gt;",reversed))
    case SCon{'"',rest}: escapeXml(rest,String.reverse.go("&quot;",reversed))
    case SCon{'\'',rest}: escapeXml(rest,String.reverse.go("&apos;",reversed))
    case SCon{char,rest}: escapeXml(rest,SCon{char,reversed})

def skillEntries(skills: List<&2,Skill>,reversed: List<&2,String>) -> List<&2,String>:
  match skills:
    case Nil{}: List.reverse(&2,String,reversed)
    case Skill{_,_,_,_,_,True{}} <> rest: skillEntries(rest,reversed)
    case Skill{name,description,filePath,_,_,False{}} <> rest:
      skillEntries(rest,("  <skill>\n    <name>" ++ escapeXml(name,"") ++ "</name>\n    <description>" ++ escapeXml(description,"") ++ "</description>\n    <location>" ++ escapeXml(filePath,"") ++ "</location>\n  </skill>") <> reversed)

def readInstruction(tool: FileReadTool) -> String:
  match tool:
    case Read{}: "Use the read tool to load a skill's file when the task matches its description."
    case Bash{}: "Use bash to load a skill's file when the task matches its description."

def formatted(entries: List<&2,String>,tool: FileReadTool) -> String:
  match entries:
    case Nil{}: ""
    case first <> rest:
      "\n\nThe following skills provide specialized instructions for specific tasks.\n" ++ readInstruction(tool) ++ "\nWhen a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.\n\n<available_skills>\n" ++ String.join(first <> rest,"\n") ++ "\n</available_skills>"

# Callers choose the read tool explicitly; the upstream default is Read{}.
def formatSkillsForPrompt(skills: List<&2,Skill>,fileReadTool: FileReadTool) -> String:
  formatted(skillEntries(skills,Nil{}),fileReadTool)

type SkillFrontmatter is Data:
  SkillFrontmatter{name: Maybe<&2,String>,description: Maybe<&2,String>,disableModelInvocation: Bool}
type LoadSkillsResult is Data:
  LoadSkillsResult{skills: List<&2,Skill>,diagnostics: List<&2,D.ResourceDiagnostic>}
type LoadSkillsFromDirOptions is Data:
  LoadSkillsFromDirOptions{dir: String,source: String}
type LoadSkillsOptions is Data:
  LoadSkillsOptions{cwd: String,agentDir: String,skillPaths: List<&2,String>,includeDefaults: Bool}
def emptyResult() -> LoadSkillsResult: LoadSkillsResult{Nil{},Nil{}}
def warning(path: String,message: String) -> LoadSkillsResult:
  LoadSkillsResult{Nil{},D.warning(message,path) <> Nil{}}
def basenameParts(parts: List<&2,String>,last: String) -> String:
  match parts:
    case Nil{}: last
    case "" <> rest: basenameParts(rest,last)
    case name <> rest: basenameParts(rest,name)
def basename(path: String) -> String: basenameParts(Strings.split(path,'/'),"")
def parentReversed(path: String) -> String:
  match path:
    case SNil{}: "."
    case SCon{'/',SNil{}}: "/"
    case SCon{'/',rest}: String.reverse(rest)
    case SCon{_,rest}: parentReversed(rest)
def parent(path: String) -> String: parentReversed(String.reverse(path))
def sourceInfo(+filePath: String,+baseDir: String,source: String) -> SourceInfo:
  match source:
    case "user": SourceInfo{filePath,"local",User{},TopLevel{},Some{baseDir}}
    case "project": SourceInfo{filePath,"local",Project{},TopLevel{},Some{baseDir}}
    case "path": SourceInfo{filePath,"local",Temporary{},TopLevel{},Some{baseDir}}
    case other: SourceInfo{filePath,other,Temporary{},TopLevel{},Some{baseDir}}

def nameCharacters(value: String,valid: Bool) -> Bool:
  match value:
    case SNil{}: valid
    case SCon{Chr{+code},rest}: nameCharacters(rest,valid && ((U32.is_ge(code,97) && U32.is_le(code,122)) || (U32.is_ge(code,48) && U32.is_le(code,57)) || U32.is_eq(code,45)))
def consecutive(value: String,previous: Bool) -> Bool:
  match value:
    case SNil{}: False{}
    case SCon{+char,rest}: Bool.pick(Unit -> Bool,previous && Char.is_eq(char,'-'),_ => True{},_ => consecutive(rest,Char.is_eq(char,'-')))(Unit{})
def validateName(+name: String) -> List<&2,String>:
  +count = Yaml.length(name,0n)
  List.concat(&2,String,
    Bool.pick(List<&2,String>,Nat.is_gt(count,64n),("name exceeds 64 characters (" ++ Nat.show(count) ++ ")") <> Nil{},Nil{}) <>
    Bool.pick(List<&2,String>,String.is_empty(name) || Bool.not(nameCharacters(name,True{})),"name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)" <> Nil{},Nil{}) <>
    Bool.pick(List<&2,String>,String.starts_with(name,"-") || String.ends_with(name,"-"),"name must not start or end with a hyphen" <> Nil{},Nil{}) <>
    Bool.pick(List<&2,String>,consecutive(name,False{}),"name must not contain consecutive hyphens" <> Nil{},Nil{}) <> Nil{})
def validateDescription(value: Maybe<&2,String>) -> List<&2,String>:
  match value:
    case None{}: "description is required" <> Nil{}
    case Some{+description}:
      +count = Yaml.length(description,0n)
      Bool.pick(List<&2,String>,String.is_empty(Frontmatter.trim(description)),"description is required" <> Nil{},
        Bool.pick(List<&2,String>,Nat.is_gt(count,1024n),("description exceeds 1024 characters (" ++ Nat.show(count) ++ ")") <> Nil{},Nil{}))
def warnings(messages: List<&2,String>,+path: String) -> List<&2,D.ResourceDiagnostic>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: D.warning(message,path) <> warnings(rest,path)
def optionalText(value: Maybe<&2,Yaml.Value>,name: String) -> Result<&2,&2,String,Maybe<&2,String>>:
  match value:
    case None{}: Done{None{}}
    case Some{Yaml.Text{value}}: Done{Some{value}}
    case _: Fail{"frontmatter " ++ name ++ " must be a string"}
def metadataFields(name: Result<&2,&2,String,Maybe<&2,String>>,description: Result<&2,&2,String,Maybe<&2,String>>,disabled: Maybe<&2,Yaml.Value>) -> Result<&2,&2,String,SkillFrontmatter>:
  match name description disabled:
    case Fail{message} _ _: Fail{message}
    case _ Fail{message} _: Fail{message}
    case Done{name} Done{description} None{}: Done{SkillFrontmatter{name,description,False{}}}
    case Done{name} Done{description} Some{Yaml.Boolean{disabled}}: Done{SkillFrontmatter{name,description,disabled}}
    case _ _ _: Fail{"frontmatter disable-model-invocation must be a boolean"}
def metadata(+fields: R.Record<Yaml.Value>) -> Result<&2,&2,String,SkillFrontmatter>:
  metadataFields(optionalText(R.get(Yaml.Value,fields,"name"),"name"),optionalText(R.get(Yaml.Value,fields,"description"),"description"),R.get(Yaml.Value,fields,"disable-model-invocation"))
def chosenName(value: Maybe<&2,String>,fallback: String) -> String:
  match value:
    case None{}: fallback
    case Some{""}: fallback
    case Some{value}: value
def validatedSkill(value: SkillFrontmatter,+path: String,source: String,declared: Bool) -> LoadSkillsResult:
  match value:
    case SkillFrontmatter{givenName,+description,disabled}:
      +directory = parent(path)
      +name = chosenName(givenName,basename(directory))
      +text = Maybe.default(&2,String,description,"")
      +hasDescription = Bool.not(String.is_empty(Frontmatter.trim(text)))
      Bool.pick(Unit -> LoadSkillsResult,Bool.not(declared) && Bool.not(hasDescription),_ => emptyResult(),_ =>
        LoadSkillsResult{Bool.pick(List<&2,Skill>,hasDescription,Skill{name,text,path,directory,sourceInfo(path,directory,source),disabled} <> Nil{},Nil{}),
          warnings(List.append(&2,String,validateDescription(description),validateName(name)),path)})(Unit{})
def parsedMetadata(value: Result<&2,&2,String,SkillFrontmatter>,+path: String,source: String,declared: Bool) -> LoadSkillsResult:
  match value:
    case Fail{message}: warning(path,message)
    case Done{fields}: validatedSkill(fields,path,source,declared)
def parsedSkill(result: Yaml.ResultOf(Frontmatter.Frontmatter),+path: String,source: String) -> LoadSkillsResult:
  match result:
    case Fail{cause}: Bool.pick(LoadSkillsResult,Strings.equal(basename(path),"SKILL.md"),warning(path,Yaml.errorMessage(cause)),emptyResult())
    case Done{Frontmatter.Frontmatter{fields,_}}: parsedMetadata(metadata(fields),path,source,Strings.equal(basename(path),"SKILL.md"))
def decodedSkill(value: Result<&2,&2,Utf8.Error,String>,path: String,source: String) -> LoadSkillsResult:
  match value:
    case Fail{_}: warning(path,"Invalid UTF-8 in skill file")
    case Done{content}: parsedSkill(Frontmatter.parseFrontmatter(content),path,source)
def fileError(error: FS.Error) -> String:
  match error:
    case FS.System{_,message}: message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close
    case FS.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
def readSkill(value: Result<&2,&2,FS.Error,List<&2,U32>>,path: String,source: String) -> LoadSkillsResult:
  match value:
    case Fail{cause}: warning(path,fileError(cause))
    case Done{bytes}: decodedSkill(Utf8.decodeWith(Utf8.Preserve{},bytes),path,source)
def loadSkillFromFile(+filePath: String,source: String) -> IO(LoadSkillsResult):
  do IO<LoadSkillsResult>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(filePath)
    return readSkill(bytes,filePath,source)

# Discovery uses a depth-first work list. The immutable matcher is threaded
# across visits so nested ignore files retain the upstream ordered precedence.
type DiscoveryWork is Data:
  Visit{path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>}
  Entries{path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>,entries: List<&2,FS.DirectoryEntry>}
type Discovery is Data:
  Discovery{work: List<&2,DiscoveryWork>,matcher: Ignore.Matcher,skills: List<&2,Skill>,diagnostics: List<&2,D.ResourceDiagnostic>}
type Rules is Data:
  Rules{matcher: Ignore.Matcher,diagnostics: List<&2,D.ResourceDiagnostic>}
def collectSkills(values: List<&2,Skill>,reversed: List<&2,Skill>) -> List<&2,Skill>:
  match values:
    case Nil{}: reversed
    case first <> rest: collectSkills(rest,first <> reversed)
def collectDiagnostics(values: List<&2,D.ResourceDiagnostic>,reversed: List<&2,D.ResourceDiagnostic>) -> List<&2,D.ResourceDiagnostic>:
  match values:
    case Nil{}: reversed
    case first <> rest: collectDiagnostics(rest,first <> reversed)
def added(state: Discovery,result: LoadSkillsResult) -> Discovery:
  match state result:
    case Discovery{work,matcher,skills,diagnostics} LoadSkillsResult{newSkills,newDiagnostics}:
      Discovery{work,matcher,collectSkills(newSkills,skills),collectDiagnostics(newDiagnostics,diagnostics)}
def noted(state: Discovery,path: String,message: String) -> Discovery: added(state,warning(path,message))
def known(values: List<&2,String>,+value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case first <> rest: Bool.pick(Unit -> Bool,Strings.equal(first,value),_ => True{},_ => known(rest,value))(Unit{})
def joinedRelative(parent: String,name: String) -> String:
  match parent:
    case "": name
    case other: other ++ "/" ++ name
def stripLeadingSlash(value: String) -> String:
  match value:
    case SCon{'/',rest}: rest
    case other: other
def prefixedPattern(line: String,prefix: String) -> String:
  match line:
    case SCon{'!',rest}: "!" ++ prefix ++ stripLeadingSlash(rest)
    case SCon{'\\',SCon{'!',rest}}: prefix ++ "\\!" ++ rest
    case other: prefix ++ stripLeadingSlash(other)
def prefixIgnorePattern(+line: String,prefix: String) -> Maybe<&2,String>:
  +trimmed = Frontmatter.trim(line)
  Bool.pick(Maybe<&2,String>,String.is_empty(trimmed) || String.starts_with(trimmed,"#"),None{},Some{prefixedPattern(line,prefix)})
def ignorePatterns(lines: List<&2,String>,+prefix: String,+reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: ignorePatterns(rest,prefix,Maybe.default(&2,List<&2,String>,Maybe.map(&2,String,List<&2,String>,value => value <> reversed,prefixIgnorePattern(line,prefix)),reversed))
def ruleAdded(result: Result<&2,&2,Ignore.Error,Ignore.Matcher>,original: Ignore.Matcher,diagnostics: List<&2,D.ResourceDiagnostic>,path: String) -> Rules:
  match result:
    case Done{matcher}: Rules{matcher,diagnostics}
    case Fail{cause}: Rules{original,D.warning(Ignore.errorMessage(cause),path) <> diagnostics}
def decodedRules(value: Result<&2,&2,Utf8.Error,String>,+matcher: Ignore.Matcher,diagnostics: List<&2,D.ResourceDiagnostic>,path: String,+relative: String) -> Rules:
  match value:
    case Fail{_}: Rules{matcher,D.warning("Invalid UTF-8 ignore file",path) <> diagnostics}
    case Done{content}:
      prefix = Bool.pick(String,String.is_empty(relative),"",relative ++ "/")
      ruleAdded(Ignore.add(matcher,ignorePatterns(Strings.split(Frontmatter.normalized(content),'\n'),prefix,Nil{})),matcher,diagnostics,path)
def readRules(value: Result<&2,&2,FS.Error,List<&2,U32>>,rules: Rules,path: String,relative: String) -> Rules:
  match value rules:
    case Fail{FS.System{2,_}} prior: prior
    case Fail{cause} Rules{matcher,diagnostics}: Rules{matcher,D.warning(fileError(cause),path) <> diagnostics}
    case Done{bytes} Rules{matcher,diagnostics}: decodedRules(Utf8.decodeWith(Utf8.Preserve{},bytes),matcher,diagnostics,path,relative)
def addIgnoreFiles(files: List<&2,String>,+directory: String,+relative: String,rules: Rules) -> IO(Rules):
  match files:
    case Nil{}: IO.pure(Rules,rules)
    case name <> rest:
      +path = FS.child(directory,name)
      do IO<Rules>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        addIgnoreFiles(rest,directory,relative,readRules(bytes,rules,path,relative))
def entryBefore(left: FS.DirectoryEntry,right: FS.DirectoryEntry) -> Bool:
  match left right:
    case FS.DirectoryEntry{a,_} FS.DirectoryEntry{b,_}: String.is_le(a,b)
def declared(entries: List<&2,FS.DirectoryEntry>) -> Maybe<&2,FS.FileKind>:
  match entries:
    case Nil{}: None{}
    case FS.DirectoryEntry{+name,kind} <> rest:
      Bool.pick(Unit -> Maybe<&2,FS.FileKind>,Strings.equal(name,"SKILL.md"),_ => Some{kind},_ => declared(rest))(Unit{})
def followed(path: String,kind: FS.FileKind) -> IO(Result<&2,&2,FS.Error,FS.FileKind>):
  match kind:
    case FS.SymbolicLink{}: FS.fileKind(path)
    case other: IO.pure(Result<&2,&2,FS.Error,FS.FileKind>,Done{other})
def presentKind(path: String,kind: Maybe<&2,FS.FileKind>) -> IO(Result<&2,&2,FS.Error,FS.FileKind>):
  match kind:
    case None{}: IO.pure(Result<&2,&2,FS.Error,FS.FileKind>,Done{FS.Other{}})
    case Some{kind}: followed(path,kind)
def scanState(path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>,entries: List<&2,FS.DirectoryEntry>,state: Discovery) -> Discovery:
  match state:
    case Discovery{work,matcher,skills,diagnostics}: Discovery{Entries{path,relative,rootFiles,ancestors,entries} <> work,matcher,skills,diagnostics}
def rootSkill(eligible: Result<&2,&2,Ignore.Error,Bool>,+path: String,source: String,fallback: Discovery,done: Discovery) -> IO(Discovery):
  match eligible:
    case Fail{cause}: IO.pure(Discovery,noted(fallback,path,Ignore.errorMessage(cause)))
    case Done{True{}}: IO.pure(Discovery,fallback)
    case Done{False{}}:
      do IO<Discovery>:
        result : LoadSkillsResult <- loadSkillFromFile(path,source)
        return added(done,result)
def chooseRoot(kind: Result<&2,&2,FS.Error,FS.FileKind>,+path: String,+relative: String,rootFiles: Bool,ancestors: List<&2,String>,entries: List<&2,FS.DirectoryEntry>,source: String,+state: Discovery) -> IO(Discovery):
  match kind state:
    case Done{FS.RegularFile{}} Discovery{_,matcher,_,_}:
      rootSkill(Ignore.ignores(matcher,joinedRelative(relative,"SKILL.md")),FS.child(path,"SKILL.md"),source,scanState(path,relative,rootFiles,ancestors,entries,state),state)
    case _ _: IO.pure(Discovery,scanState(path,relative,rootFiles,ancestors,entries,state))
def withRules(rules: Rules,+path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>,+entries: List<&2,FS.DirectoryEntry>,source: String,state: Discovery) -> IO(Discovery):
  match rules state:
    case Rules{matcher,issues} Discovery{work,_,skills,diagnostics}:
      do IO<Discovery>:
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- presentKind(FS.child(path,"SKILL.md"),declared(entries))
        chooseRoot(kind,path,relative,rootFiles,ancestors,entries,source,Discovery{work,matcher,skills,List.append(&2,D.ResourceDiagnostic,issues,diagnostics)})
def directoryRead(result: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>,+path: String,+relative: String,rootFiles: Bool,ancestors: List<&2,String>,source: String,+state: Discovery) -> IO(Discovery):
  match result state:
    case Fail{FS.System{2,_}} _: IO.pure(Discovery,state)
    case Fail{cause} _: IO.pure(Discovery,noted(state,path,fileError(cause)))
    case Done{entries} Discovery{_,matcher,_,_}:
      do IO<Discovery>:
        rules : Rules <- addIgnoreFiles(".gitignore" <> ".ignore" <> ".fdignore" <> Nil{},path,relative,Rules{matcher,Nil{}})
        withRules(rules,path,relative,rootFiles,ancestors,Sort.sort(~FS.DirectoryEntry,~entryBefore,entries),source,state)
def canonical(result: Result<&2,&2,FS.Error,String>,fallback: String) -> String:
  match result:
    case Done{value}: value
    case Fail{_}: fallback
def visitCanonical(+real: String,+path: String,relative: String,rootFiles: Bool,+ancestors: List<&2,String>,source: String,+state: Discovery) -> IO(Discovery):
  Bool.pick(Unit -> IO(Discovery),known(ancestors,real),_ => IO.pure(Discovery,noted(state,path,"Recursive skill directory symlink")),_ =>
    do IO<Discovery>:
      entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(path)
      directoryRead(entries,path,relative,rootFiles,real <> ancestors,source,state))(Unit{})
def visitDirectory(+path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>,source: String,state: Discovery) -> IO(Discovery):
  do IO<Discovery>:
    real : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
    visitCanonical(canonical(real,path),path,relative,rootFiles,ancestors,source,state)
def pushDirectory(path: String,relative: String,ancestors: List<&2,String>,state: Discovery) -> Discovery:
  match state:
    case Discovery{work,matcher,skills,diagnostics}: Discovery{Visit{path,relative,False{},ancestors} <> work,matcher,skills,diagnostics}
def acceptedEntry(kind: FS.FileKind,+path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>,source: String,+state: Discovery) -> IO(Discovery):
  match kind:
    case FS.Directory{}: IO.pure(Discovery,pushDirectory(path,relative,ancestors,state))
    case FS.RegularFile{}:
      Bool.pick(Unit -> IO(Discovery),rootFiles && String.ends_with(path,".md"),_ =>
        do IO<Discovery>:
          result : LoadSkillsResult <- loadSkillFromFile(path,source)
          return added(state,result),_ => IO.pure(Discovery,state))(Unit{})
    case _: IO.pure(Discovery,state)
def consideredEntry(ignore: Result<&2,&2,Ignore.Error,Bool>,kind: FS.FileKind,path: String,relative: String,rootFiles: Bool,ancestors: List<&2,String>,source: String,state: Discovery) -> IO(Discovery):
  match ignore:
    case Fail{cause}: IO.pure(Discovery,noted(state,path,Ignore.errorMessage(cause)))
    case Done{True{}}: IO.pure(Discovery,state)
    case Done{False{}}: acceptedEntry(kind,path,relative,rootFiles,ancestors,source,state)
def isDirectory(kind: FS.FileKind) -> Bool:
  match kind:
    case FS.Directory{}: True{}
    case _: False{}
def resolvedEntry(value: Result<&2,&2,FS.Error,FS.FileKind>,path: String,+relative: String,rootFiles: Bool,ancestors: List<&2,String>,source: String,+state: Discovery) -> IO(Discovery):
  match value state:
    case Fail{_} _: IO.pure(Discovery,state)
    case Done{+kind} Discovery{_,matcher,_,_}:
      target = Bool.pick(String,isDirectory(kind),relative ++ "/",relative)
      consideredEntry(Ignore.ignores(matcher,target),kind,path,relative,rootFiles,ancestors,source,state)
def entry(item: FS.DirectoryEntry,+directory: String,+relative: String,rootFiles: Bool,ancestors: List<&2,String>,source: String,+state: Discovery) -> IO(Discovery):
  match item:
    case FS.DirectoryEntry{+name,kind}:
      Bool.pick(Unit -> IO(Discovery),String.starts_with(name,".") || Strings.equal(name,"node_modules"),_ => IO.pure(Discovery,state),_ =>
        do IO<Discovery>:
          +path : String = FS.child(directory,name)
          result : Result<&2,&2,FS.Error,FS.FileKind> <- followed(path,kind)
          resolvedEntry(result,path,joinedRelative(relative,name),rootFiles,ancestors,source,state))(Unit{})
def discoveryStep(source: String,state: Discovery) -> IO(Discovery):
  match state:
    case Discovery{Nil{},matcher,skills,diagnostics}: IO.pure(Discovery,Discovery{Nil{},matcher,skills,diagnostics})
    case Discovery{Visit{path,relative,rootFiles,ancestors} <> rest,matcher,skills,diagnostics}:
      visitDirectory(path,relative,rootFiles,ancestors,source,Discovery{rest,matcher,skills,diagnostics})
    case Discovery{Entries{_,_,_,_,Nil{}} <> rest,matcher,skills,diagnostics}: IO.pure(Discovery,Discovery{rest,matcher,skills,diagnostics})
    case Discovery{Entries{+path,+relative,+rootFiles,+ancestors,item <> entries} <> rest,matcher,skills,diagnostics}:
      entry(item,path,relative,rootFiles,ancestors,source,Discovery{Entries{path,relative,rootFiles,ancestors,entries} <> rest,matcher,skills,diagnostics})
# Directory topology is external; canonical ancestor checks stop symlink cycles.
@unsafe def discover(+source: String,state: Discovery) -> IO(LoadSkillsResult):
  match state:
    case Discovery{Nil{},_,skills,diagnostics}: IO.pure(LoadSkillsResult,LoadSkillsResult{List.reverse(&2,Skill,skills),List.reverse(&2,D.ResourceDiagnostic,diagnostics)})
    case other:
      do IO<LoadSkillsResult>:
        next : Discovery <- discoveryStep(source,other)
        discover(source,next)
def loadSkillsFromDir(options: LoadSkillsFromDirOptions) -> IO(LoadSkillsResult):
  match options:
    case LoadSkillsFromDirOptions{dir,source}: discover(source,Discovery{Visit{dir,"",True{},Nil{}} <> Nil{},Ignore.empty(),Nil{},Nil{}})

# Configured locations add user, project, then explicit resources. Name winners
# and canonical-file deduplication remain separate: a losing collision does not
# reserve its path. Ordinary diagnostics precede collision diagnostics.
type Collection is Data:
  Collection{skills: R.Record<Skill>,realPaths: Strings.StringSet,diagnostics: List<&2,D.ResourceDiagnostic>,collisions: List<&2,D.ResourceDiagnostic>}
def collisionOrInsert(existing: Maybe<&2,Skill>,+skill: Skill,real: String,skills: R.Record<Skill>,realPaths: Strings.StringSet,diagnostics: List<&2,D.ResourceDiagnostic>,collisions: List<&2,D.ResourceDiagnostic>) -> Collection:
  match existing skill:
    case None{} Skill{name,_,_,_,_,_}: Collection{R.set(Skill,skills,name,skill),Strings.insert(realPaths,real),diagnostics,collisions}
    case Some{Skill{_,_,winner,_,_,_}} Skill{+name,_,+path,_,_,_}:
      Collection{skills,realPaths,diagnostics,D.ResourceDiagnostic{D.Collision{},"name \"" ++ name ++ "\" collision",Some{path},Some{D.ResourceCollision{D.Skill{},name,winner,path,None{},None{}}}} <> collisions}
def collectOne(+skill: Skill,+real: String,collection: Collection) -> Collection:
  match skill collection:
    case Skill{name,_,_,_,_,_} Collection{+skills,+realPaths,+diagnostics,+collisions}:
      Bool.pick(Unit -> Collection,Strings.contains(realPaths,real),_ => Collection{skills,realPaths,diagnostics,collisions},_ =>
        collisionOrInsert(R.get(Skill,skills,name),skill,real,skills,realPaths,diagnostics,collisions))(Unit{})
def skillPath(skill: Skill) -> String:
  match skill:
    case Skill{_,_,path,_,_,_}: path
def collectValues(values: List<&2,Skill>,collection: Collection) -> IO(Collection):
  match values:
    case Nil{}: IO.pure(Collection,collection)
    case +skill <> rest:
      +path = skillPath(skill)
      do IO<Collection>:
        real : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
        collectValues(rest,collectOne(skill,canonical(real,path),collection))
def collectResult(result: LoadSkillsResult,collection: Collection) -> IO(Collection):
  match result collection:
    case LoadSkillsResult{values,issues} Collection{skills,realPaths,diagnostics,collisions}:
      collectValues(values,Collection{skills,realPaths,collectDiagnostics(issues,diagnostics),collisions})
def skillValues(fields: List<&2,R.Property<Skill>>) -> List<&2,Skill>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{_,value} <> rest: value <> skillValues(rest)
def collected(collection: Collection) -> LoadSkillsResult:
  match collection:
    case Collection{skills,_,diagnostics,collisions}: LoadSkillsResult{skillValues(R.entries(Skill,skills)),List.append(&2,D.ResourceDiagnostic,List.reverse(&2,D.ResourceDiagnostic,diagnostics),List.reverse(&2,D.ResourceDiagnostic,collisions))}
def under(+path: String,+directory: String) -> Bool:
  Strings.equal(path,directory) || String.starts_with(path,directory ++ "/")
def explicitSource(path: String,agentDir: String,cwd: String,includeDefaults: Bool) -> String:
  match includeDefaults:
    case True{}: "path"
    case False{}:
      +path = path
      Bool.pick(String,under(path,Path.join(agentDir,"skills")),"user",Bool.pick(String,under(path,Path.join(cwd,".pi/skills")),"project","path"))
def explicitKind(kind: Result<&2,&2,FS.Error,FS.FileKind>,+path: String,source: String) -> IO(LoadSkillsResult):
  match kind:
    case Fail{FS.System{2,_}}: IO.pure(LoadSkillsResult,warning(path,"skill path does not exist"))
    case Fail{cause}: IO.pure(LoadSkillsResult,warning(path,fileError(cause)))
    case Done{FS.Directory{}}: loadSkillsFromDir(LoadSkillsFromDirOptions{path,source})
    case Done{FS.RegularFile{}}:
      Bool.pick(Unit -> IO(LoadSkillsResult),String.ends_with(path,".md"),_ => loadSkillFromFile(path,source),_ => IO.pure(LoadSkillsResult,warning(path,"skill path is not a markdown file")))(Unit{})
    case _: IO.pure(LoadSkillsResult,warning(path,"skill path is not a markdown file"))
def explicitResolved(result: Result<&2,&2,Paths.Error,String>,raw: String,agentDir: String,cwd: String,includeDefaults: Bool) -> IO(LoadSkillsResult):
  match result:
    case Fail{_}: IO.pure(LoadSkillsResult,warning(raw,"Invalid skill path"))
    case Done{+path}:
      do IO<LoadSkillsResult>:
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        explicitKind(kind,path,explicitSource(path,agentDir,cwd,includeDefaults))
def loadPaths(paths: List<&2,String>,+environment: Paths.Environment,+cwd: String,+agentDir: String,+includeDefaults: Bool,collection: Collection) -> IO(LoadSkillsResult):
  match paths:
    case Nil{}: IO.pure(LoadSkillsResult,collected(collection))
    case +raw <> rest:
      do IO<LoadSkillsResult>:
        result : LoadSkillsResult <- explicitResolved(Paths.resolvePath(environment,raw,cwd,Paths.PathInputOptions{True{},True{},None{},False{},False{}}),raw,agentDir,cwd,includeDefaults)
        next : Collection <- collectResult(result,collection)
        loadPaths(rest,environment,cwd,agentDir,includeDefaults,next)
def initialCollection() -> Collection: Collection{R.new(Skill),Strings.empty(),Nil{},Nil{}}
def defaultsLoaded(includeDefaults: Bool,environment: Paths.Environment,+cwd: String,+agentDir: String,paths: List<&2,String>) -> IO(LoadSkillsResult):
  match includeDefaults:
    case False{}: loadPaths(paths,environment,cwd,agentDir,False{},initialCollection())
    case True{}:
      do IO<LoadSkillsResult>:
        user : LoadSkillsResult <- loadSkillsFromDir(LoadSkillsFromDirOptions{Path.join(agentDir,"skills"),"user"})
        first : Collection <- collectResult(user,initialCollection())
        project : LoadSkillsResult <- loadSkillsFromDir(LoadSkillsFromDirOptions{Path.join(cwd,".pi/skills"),"project"})
        second : Collection <- collectResult(project,first)
        loadPaths(paths,environment,cwd,agentDir,True{},second)
def locations(cwd: Result<&2,&2,Paths.Error,String>,agentDir: Result<&2,&2,Paths.Error,String>,environment: Paths.Environment,paths: List<&2,String>,includeDefaults: Bool) -> IO(LoadSkillsResult):
  match cwd agentDir:
    case Fail{_} _: IO.pure(LoadSkillsResult,warning("","Invalid skill working directory"))
    case _ Fail{_}: IO.pure(LoadSkillsResult,warning("","Invalid agent directory"))
    case Done{cwd} Done{agentDir}: defaultsLoaded(includeDefaults,environment,cwd,agentDir,paths)
# Configuration supplies agentDir explicitly; the caller owns config defaults.
def loadSkills(+environment: Paths.Environment,options: LoadSkillsOptions) -> IO(LoadSkillsResult):
  match options:
    case LoadSkillsOptions{cwd,agentDir,paths,includeDefaults}:
      locations(Paths.resolvePath(environment,cwd,"",Paths.defaults()),Paths.resolvePath(environment,agentDir,"",Paths.defaults()),environment,paths,includeDefaults)
