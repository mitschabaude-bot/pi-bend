import Base
import ./settings-manager.bend as Settings
import ./skills.bend as Skills
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/ignore.bend as Ignore
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/stable-sort.bend as Sort
import ../../../runtime/src/minimatch.bend as Minimatch
import ../utils/git.bend as Git
import ./settings-diagnostics.bend as Diagnostics
import ../../../runtime/src/semver.bend as Semver
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/sha256.bend as Sha256
import ../../../runtime/src/utf8.bend as Utf8

# upstream PackageManager.resolve for local resources: the skills, prompt
# templates and themes named by the global and project settings (plain paths
# and enable/disable patterns) and those auto-discovered under the agent
# directory, the project's .pi directory and the .agents skill directories,
# each enabled unless an override pattern disables it. Package sources
# (settings `packages`, npm and git installs) and extensions are not ported.

type ResourceType is Data:
  SkillResources{}
  PromptResources{}
  ThemeResources{}

type Source is Data:
  Local{}
  Auto{}

type Scope is Data:
  ProjectScope{}
  UserScope{}

type PathMetadata is Data:
  PathMetadata{source: Source, scope: Scope, baseDir: Maybe<&2, String>}

type ResolvedResource is Data:
  ResolvedResource{path: String, enabled: Bool, metadata: PathMetadata}

type ResolvedPaths is Data:
  ResolvedPaths{skills: List<&2, ResolvedResource>, prompts: List<&2, ResolvedResource>, themes: List<&2, ResolvedResource>}

# Patterns
# --------

def globMatches(path: String, pattern: String) -> Bool: Minimatch.minimatch(path, pattern)

def isOverridePattern(+entry: String) -> Bool:
  String.starts_with(entry, "!") || String.starts_with(entry, "+") || String.starts_with(entry, "-")

def hasGlob(+entry: String) -> Bool:
  String.contains(entry, "*") || String.contains(entry, "?")

def isPattern(+entry: String) -> Bool: isOverridePattern(entry) || hasGlob(entry)

def isSkillFile(path: String) -> Bool: String.eq(Path.basename(path), "SKILL.md")

def anyGlob(+path: String, patterns: List<&2, String>) -> Bool:
  match patterns:
    case Nil{}: False{}
    case pattern <> rest: globMatches(path, pattern) || anyGlob(path, rest)

# The names a pattern may match: the path relative to its base, its name and
# the full path, and for SKILL.md files the same for the skill directory.
def candidates(+filePath: String, +baseDir: String) -> List<&2, String>:
  +parent = Skills.parent(filePath)
  Bool.pick(List<&2, String>, isSkillFile(filePath),
    Path.relative(baseDir, filePath) <> Path.basename(filePath) <> filePath <> Path.relative(baseDir, parent) <> Path.basename(parent) <> parent <> Nil{},
    Path.relative(baseDir, filePath) <> Path.basename(filePath) <> filePath <> Nil{})

def anyCandidate(candidates: List<&2, String>, +patterns: List<&2, String>) -> Bool:
  match candidates:
    case Nil{}: False{}
    case candidate <> rest: anyGlob(candidate, patterns) || anyCandidate(rest, patterns)

# upstream matchesAnyPattern: rel, name and path first, then the skill directory.
def matchesAnyPattern(filePath: String, patterns: List<&2, String>, baseDir: String) -> Bool:
  anyCandidate(candidates(filePath, baseDir), patterns)

def normalizeExactPattern(pattern: String) -> String:
  match pattern:
    case SCon{'.', SCon{'/', rest}}: rest
    case SCon{'.', SCon{'\\', rest}}: rest
    case other: other

def exactCandidates(+filePath: String, +baseDir: String) -> List<&2, String>:
  +parent = Skills.parent(filePath)
  Bool.pick(List<&2, String>, isSkillFile(filePath),
    Path.relative(baseDir, filePath) <> filePath <> Path.relative(baseDir, parent) <> parent <> Nil{},
    Path.relative(baseDir, filePath) <> filePath <> Nil{})

def listed(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case first <> rest: String.eq(first, value) || listed(rest, value)

def anyExact(+candidates: List<&2, String>, patterns: List<&2, String>) -> Bool:
  match patterns:
    case Nil{}: False{}
    case pattern <> rest: listed(candidates, normalizeExactPattern(pattern)) || anyExact(candidates, rest)

# upstream matchesAnyExactPattern: "./" is dropped from the pattern.
def matchesAnyExactPattern(filePath: String, patterns: List<&2, String>, baseDir: String) -> Bool:
  anyExact(exactCandidates(filePath, baseDir), patterns)

type PatternKinds is Data:
  PatternKinds{includes: List<&2, String>, excludes: List<&2, String>, forceIncludes: List<&2, String>, forceExcludes: List<&2, String>}

def sortedKind(+pattern: String, kinds: PatternKinds) -> PatternKinds:
  match pattern kinds:
    case SCon{'+', rest} PatternKinds{includes, excludes, forceIncludes, forceExcludes}: PatternKinds{includes, excludes, rest <> forceIncludes, forceExcludes}
    case SCon{'-', rest} PatternKinds{includes, excludes, forceIncludes, forceExcludes}: PatternKinds{includes, excludes, forceIncludes, rest <> forceExcludes}
    case SCon{'!', rest} PatternKinds{includes, excludes, forceIncludes, forceExcludes}: PatternKinds{includes, rest <> excludes, forceIncludes, forceExcludes}
    case other PatternKinds{includes, excludes, forceIncludes, forceExcludes}: PatternKinds{other <> includes, excludes, forceIncludes, forceExcludes}

def patternKinds(patterns: List<&2, String>, kinds: PatternKinds) -> PatternKinds:
  match patterns:
    case Nil{}: kinds
    case pattern <> rest: patternKinds(rest, sortedKind(pattern, kinds))

def sameBool(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def keepMatching(paths: List<&2, String>, +patterns: List<&2, String>, +baseDir: String, +keep: Bool) -> List<&2, String>:
  match paths:
    case Nil{}: Nil{}
    case +path <> +rest:
      Bool.pick(Unit -> List<&2, String>, sameBool(matchesAnyPattern(path, patterns, baseDir), keep),
        _ => path <> keepMatching(rest, patterns, baseDir, keep),
        _ => keepMatching(rest, patterns, baseDir, keep))(Unit{})

def withoutExact(paths: List<&2, String>, +patterns: List<&2, String>, +baseDir: String) -> List<&2, String>:
  match paths:
    case Nil{}: Nil{}
    case +path <> +rest:
      Bool.pick(Unit -> List<&2, String>, matchesAnyExactPattern(path, patterns, baseDir),
        _ => withoutExact(rest, patterns, baseDir),
        _ => path <> withoutExact(rest, patterns, baseDir))(Unit{})

def forcedBack(all: List<&2, String>, +result: List<&2, String>, +patterns: List<&2, String>, +baseDir: String) -> List<&2, String>:
  match all:
    case Nil{}: result
    case +path <> +rest:
      Bool.pick(Unit -> List<&2, String>, Bool.not(listed(result, path)) && matchesAnyExactPattern(path, patterns, baseDir),
        _ => forcedBack(rest, List.append(&2, String, result, path <> Nil{}), patterns, baseDir),
        _ => forcedBack(rest, result, patterns, baseDir))(Unit{})

def included(+all: List<&2, String>, includes: List<&2, String>, +baseDir: String) -> List<&2, String>:
  match includes:
    case Nil{}: all
    case _: keepMatching(all, includes, baseDir, True{})

def excluded(result: List<&2, String>, excludes: List<&2, String>, +baseDir: String) -> List<&2, String>:
  match excludes:
    case Nil{}: result
    case _: keepMatching(result, excludes, baseDir, False{})

# upstream applyPatterns: includes (all when none), then !excludes, then
# +force-includes of exact paths, then -force-excludes; the enabled set.
def appliedKinds(+allPaths: List<&2, String>, kinds: PatternKinds, +baseDir: String) -> List<&2, String>:
  match kinds:
    case PatternKinds{includes, excludes, forceIncludes, forceExcludes}:
      withoutExact(forcedBack(allPaths, excluded(included(allPaths, List.reverse(&2, String, includes), baseDir), List.reverse(&2, String, excludes), baseDir), List.reverse(&2, String, forceIncludes), baseDir), List.reverse(&2, String, forceExcludes), baseDir)

def applyPatterns(+allPaths: List<&2, String>, patterns: List<&2, String>, +baseDir: String) -> List<&2, String>:
  appliedKinds(allPaths, patternKinds(patterns, PatternKinds{Nil{}, Nil{}, Nil{}, Nil{}}), baseDir)

def withoutFirst(value: String) -> String:
  match value:
    case SCon{_, rest}: rest
    case SNil{}: ""

def overridePatterns(entries: List<&2, String>, +prefix: String) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> others:
      +tail = overridePatterns(others, prefix)
      Bool.pick(List<&2, String>, String.starts_with(entry, prefix), withoutFirst(entry) <> tail, tail)

# upstream isEnabledByOverrides: !excludes disable, +exact paths re-enable,
# -exact paths disable last.
def isEnabledByOverrides(+filePath: String, +patterns: List<&2, String>, +baseDir: String) -> Bool:
  +excludes = overridePatterns(patterns, "!")
  +forceIncludes = overridePatterns(patterns, "+")
  +forceExcludes = overridePatterns(patterns, "-")
  +afterExcludes = Bool.not(Bool.not(List.is_empty(&2, String, excludes)) && matchesAnyPattern(filePath, excludes, baseDir))
  +afterIncludes = afterExcludes || (Bool.not(List.is_empty(&2, String, forceIncludes)) && matchesAnyExactPattern(filePath, forceIncludes, baseDir))
  afterIncludes && Bool.not(Bool.not(List.is_empty(&2, String, forceExcludes)) && matchesAnyExactPattern(filePath, forceExcludes, baseDir))

# Discovery
# ---------

def ignoreFiles() -> List<&2, String>: ".gitignore" <> ".ignore" <> ".fdignore" <> Nil{}

def ignored(matcher: Ignore.Matcher, path: String) -> Bool:
  Result.default(&2, &2, Ignore.Error, Bool, Ignore.ignores(matcher, path), False{})

def rulesOf(rules: Skills.Rules) -> Ignore.Matcher:
  match rules:
    case Skills.Rules{matcher, _}: matcher

def entryBefore(left: FS.DirectoryEntry, right: FS.DirectoryEntry) -> Bool:
  match left right:
    case FS.DirectoryEntry{a, _} FS.DirectoryEntry{b, _}: String.is_le(a, b)

# Node's readdirSync lists entries in byte order.
def sortedEntries(result: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>) -> List<&2, FS.DirectoryEntry>:
  match result:
    case Fail{_}: Nil{}
    case Done{+entries}: Sort.sort(~FS.DirectoryEntry, ~entryBefore, entries)

def readSorted(path: String) -> IO(List<&2, FS.DirectoryEntry>):
  do IO<List<&2, FS.DirectoryEntry>>:
    entries : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(path)
    return sortedEntries(entries)

# An entry's kind with symbolic links followed; None when the target is gone.
def followedKind(path: String, kind: FS.FileKind) -> IO(Maybe<&2, FS.FileKind>):
  match kind:
    case FS.SymbolicLink{}:
      do IO<Maybe<&2, FS.FileKind>>:
        target : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind(path)
        return Result.default(&2, &2, FS.Error, Maybe<&2, FS.FileKind>, Result.map(&2, &2, FS.Error, FS.FileKind, Maybe<&2, FS.FileKind>, found => Some{found}, target), None{})
    case other: IO.pure(Maybe<&2, FS.FileKind>, Some{other})

def isRegular(kind: Maybe<&2, FS.FileKind>) -> Bool:
  match kind:
    case Some{FS.RegularFile{}}: True{}
    case _: False{}

def isDir(kind: Maybe<&2, FS.FileKind>) -> Bool:
  match kind:
    case Some{FS.Directory{}}: True{}
    case _: False{}

def hidden(+name: String) -> Bool: String.starts_with(name, ".") || String.eq(name, "node_modules")

type SkillMode is Data:
  PiSkills{}
  AgentsSkills{}

def rootFilesCount(mode: SkillMode, atRoot: Bool) -> Bool:
  match mode:
    case PiSkills{}: atRoot
    case AgentsSkills{}: Bool.not(atRoot)

type Work is Data:
  VisitDir{path: String}
  DirEntries{dir: String, entries: List<&2, FS.DirectoryEntry>}

# A depth-first walk sharing one growing ignore matcher, as upstream passes
# its ignore instance down the recursion.
type Walk is Data:
  Walk{root: String, work: List<&2, Work>, rules: Skills.Rules, found: List<&2, String>}

def relativeTo(+root: String, +path: String) -> String: Path.relative(root, path)

def withRules(walk: Walk, rules: Skills.Rules) -> Walk:
  match walk:
    case Walk{root, work, _, found}: Walk{root, work, rules, found}

def pushed(walk: Walk, item: Work) -> Walk:
  match walk:
    case Walk{root, work, rules, found}: Walk{root, item <> work, rules, found}

def foundIn(walk: Walk, path: String) -> Walk:
  match walk:
    case Walk{root, work, rules, found}: Walk{root, work, rules, path <> found}

def addedRules(+walk: Walk, +dir: String) -> IO(Walk):
  match walk:
    case Walk{+root, _, rules, _}:
      do IO<Walk>:
        next : Skills.Rules <- Skills.addIgnoreFiles(ignoreFiles(), dir, relativeTo(root, dir), rules)
        return withRules(walk, next)

# upstream collectSkillEntries: a directory with a SKILL.md is one skill;
# otherwise Markdown files count at the root (pi) or below it (.agents), and
# subdirectories are searched.
def skillFileIn(entries: List<&2, FS.DirectoryEntry>) -> Maybe<&2, FS.FileKind>:
  match entries:
    case Nil{}: None{}
    case FS.DirectoryEntry{"SKILL.md", kind} <> _: Some{kind}
    case _ <> rest: skillFileIn(rest)

def skillDirVisited(+walk: Walk, +dir: String, +entries: List<&2, FS.DirectoryEntry>, kind: Maybe<&2, FS.FileKind>) -> Walk:
  match walk:
    case Walk{root, _, +rules, _}:
      +skillFile = FS.child(dir, "SKILL.md")
      Bool.pick(Unit -> Walk, isRegular(kind) && Bool.not(ignored(rulesOf(rules), relativeTo(root, skillFile))),
        _ => foundIn(walk, skillFile),
        _ => pushed(walk, DirEntries{dir, entries}))(Unit{})

def skillKind(dir: String, declared: Maybe<&2, FS.FileKind>) -> IO(Maybe<&2, FS.FileKind>):
  match declared:
    case None{}: IO.pure(Maybe<&2, FS.FileKind>, None{})
    case Some{kind}: followedKind(FS.child(dir, "SKILL.md"), kind)

def visitSkillDir(+walk: Walk, +dir: String) -> IO(Walk):
  do IO<Walk>:
    +ruled : Walk <- addedRules(walk, dir)
    +entries : List<&2, FS.DirectoryEntry> <- readSorted(dir)
    kind : Maybe<&2, FS.FileKind> <- skillKind(dir, skillFileIn(entries))
    return skillDirVisited(ruled, dir, entries, kind)

def skillEntry(+walk: Walk, mode: SkillMode, +dir: String, +name: String, +path: String, +kind: Maybe<&2, FS.FileKind>) -> Walk:
  match walk:
    case Walk{+root, _, +rules, _}:
      +rel = relativeTo(root, path)
      Bool.pick(Unit -> Walk, isRegular(kind) && String.ends_with(name, ".md") && Bool.not(ignored(rulesOf(rules), rel)) && rootFilesCount(mode, String.eq(dir, root)),
        _ => foundIn(walk, path),
        _ => Bool.pick(Walk, isDir(kind) && Bool.not(ignored(rulesOf(rules), rel ++ "/")), pushed(walk, VisitDir{path}), walk))(Unit{})

def skillStep(+walk: Walk, mode: SkillMode, item: Work) -> IO(Walk):
  match item:
    case VisitDir{path}: visitSkillDir(walk, path)
    case DirEntries{_, Nil{}}: IO.pure(Walk, walk)
    case DirEntries{+dir, FS.DirectoryEntry{+name, kind} <> rest}:
      +next = pushed(walk, DirEntries{dir, rest})
      Bool.pick(Unit -> IO(Walk), hidden(name),
        _ => IO.pure(Walk, next),
        _ => do IO<Walk>:
          +path : String = FS.child(dir, name)
          followed : Maybe<&2, FS.FileKind> <- followedKind(path, kind)
          return skillEntry(next, mode, dir, name, path, followed))(Unit{})

def popped(walk: Walk) -> Walk & Maybe<&2, Work>:
  match walk:
    case Walk{root, Nil{}, rules, found}: (Walk{root, Nil{}, rules, found}, None{})
    case Walk{root, item <> rest, rules, found}: (Walk{root, rest, rules, found}, Some{item})

def foundOf(walk: Walk) -> List<&2, String>:
  match walk:
    case Walk{_, _, _, found}: List.reverse(&2, String, found)

def skillWalkNext(fuel: Nat, +mode: SkillMode, pair: Walk & Maybe<&2, Work>) -> IO(List<&2, String>):
  match fuel pair:
    case _ Tuple{walk, None{}}: IO.pure(List<&2, String>, foundOf(walk))
    case 0n Tuple{walk, _}: IO.pure(List<&2, String>, foundOf(walk))
    case 1n+rest Tuple{walk, Some{item}}:
      do IO<List<&2, String>>:
        next : Walk <- skillStep(walk, mode, item)
        skillWalkNext(rest, mode, popped(next))

def exists(path: String) -> IO(Bool): FS.accessible(path, 0)

def skillEntriesExisting(+dir: String, mode: SkillMode, present: Bool) -> IO(List<&2, String>):
  match present:
    case False{}: IO.pure(List<&2, String>, Nil{})
    case True{}: skillWalkNext(1000000n, mode, (Walk{dir, Nil{}, Skills.Rules{Ignore.empty(), Nil{}}, Nil{}}, Some{VisitDir{dir}}))

def collectSkillEntries(+dir: String, mode: SkillMode) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    present : Bool <- exists(dir)
    skillEntriesExisting(dir, mode, present)

# upstream collectFiles: files with the resource's extension anywhere below,
# honouring ignore files and skipping dot entries and node_modules.
def fileEntry(+walk: Walk, extension: String, +name: String, +path: String, +kind: Maybe<&2, FS.FileKind>) -> Walk:
  match walk:
    case Walk{+root, _, +rules, _}:
      +rel = relativeTo(root, path)
      Bool.pick(Unit -> Walk, isDir(kind),
        _ => Bool.pick(Walk, ignored(rulesOf(rules), rel ++ "/"), walk, pushed(walk, VisitDir{path})),
        _ => Bool.pick(Walk, isRegular(kind) && String.ends_with(name, extension) && Bool.not(ignored(rulesOf(rules), rel)), foundIn(walk, path), walk))(Unit{})

def fileStep(+walk: Walk, extension: String, item: Work) -> IO(Walk):
  match item:
    case VisitDir{+path}:
      do IO<Walk>:
        ruled : Walk <- addedRules(walk, path)
        entries : List<&2, FS.DirectoryEntry> <- readSorted(path)
        return pushed(ruled, DirEntries{path, entries})
    case DirEntries{_, Nil{}}: IO.pure(Walk, walk)
    case DirEntries{+dir, FS.DirectoryEntry{+name, kind} <> rest}:
      +next = pushed(walk, DirEntries{dir, rest})
      Bool.pick(Unit -> IO(Walk), hidden(name),
        _ => IO.pure(Walk, next),
        _ => do IO<Walk>:
          +path : String = FS.child(dir, name)
          followed : Maybe<&2, FS.FileKind> <- followedKind(path, kind)
          return fileEntry(next, extension, name, path, followed))(Unit{})

def fileWalkNext(fuel: Nat, +extension: String, pair: Walk & Maybe<&2, Work>) -> IO(List<&2, String>):
  match fuel pair:
    case _ Tuple{walk, None{}}: IO.pure(List<&2, String>, foundOf(walk))
    case 0n Tuple{walk, _}: IO.pure(List<&2, String>, foundOf(walk))
    case 1n+rest Tuple{walk, Some{item}}:
      do IO<List<&2, String>>:
        next : Walk <- fileStep(walk, extension, item)
        fileWalkNext(rest, extension, popped(next))

def filesExisting(+dir: String, extension: String, present: Bool) -> IO(List<&2, String>):
  match present:
    case False{}: IO.pure(List<&2, String>, Nil{})
    case True{}: fileWalkNext(1000000n, extension, (Walk{dir, Nil{}, Skills.Rules{Ignore.empty(), Nil{}}, Nil{}}, Some{VisitDir{dir}}))

def collectFiles(+dir: String, extension: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    present : Bool <- exists(dir)
    filesExisting(dir, extension, present)

def extensionOf(kind: ResourceType) -> String:
  match kind:
    case SkillResources{}: ".md"
    case PromptResources{}: ".md"
    case ThemeResources{}: ".json"

# upstream collectResourceFiles.
def collectResourceFiles(+dir: String, kind: ResourceType) -> IO(List<&2, String>):
  match kind:
    case SkillResources{}: collectSkillEntries(dir, PiSkills{})
    case _: collectFiles(dir, extensionOf(kind))

# upstream collectAutoPromptEntries / collectAutoThemeEntries: the directory's
# own files only.
def autoEntries(+dir: String, +rules: Skills.Rules, +extension: String, entries: List<&2, FS.DirectoryEntry>) -> IO(List<&2, String>):
  match entries:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case FS.DirectoryEntry{+name, kind} <> +rest:
      Bool.pick(Unit -> IO(List<&2, String>), hidden(name),
        _ => autoEntries(dir, rules, extension, rest),
        _ => do IO<List<&2, String>>:
          +path : String = FS.child(dir, name)
          followed : Maybe<&2, FS.FileKind> <- followedKind(path, kind)
          +later : List<&2, String> <- autoEntries(dir, rules, extension, rest)
          return Bool.pick(List<&2, String>, isRegular(followed) && String.ends_with(name, extension) && Bool.not(ignored(rulesOf(rules), relativeTo(dir, path))), path <> later, later))(Unit{})

def autoExisting(+dir: String, extension: String, present: Bool) -> IO(List<&2, String>):
  match present:
    case False{}: IO.pure(List<&2, String>, Nil{})
    case True{}:
      do IO<List<&2, String>>:
        rules : Skills.Rules <- Skills.addIgnoreFiles(ignoreFiles(), dir, "", Skills.Rules{Ignore.empty(), Nil{}})
        entries : List<&2, FS.DirectoryEntry> <- readSorted(dir)
        autoEntries(dir, rules, extension, entries)

def collectAutoEntries(+dir: String, extension: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    present : Bool <- exists(dir)
    autoExisting(dir, extension, present)

# upstream collectFilesFromPaths: existing files as given, directories searched.
def pathFiles(+path: String, kind: ResourceType, found: Result<&2, &2, FS.Error, FS.FileKind>) -> IO(List<&2, String>):
  match found:
    case Done{FS.RegularFile{}}: IO.pure(List<&2, String>, path <> Nil{})
    case Done{FS.Directory{}}: collectResourceFiles(path, kind)
    case _: IO.pure(List<&2, String>, Nil{})

def collectFilesFromPaths(paths: List<&2, String>, +kind: ResourceType) -> IO(List<&2, String>):
  match paths:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +path <> rest:
      do IO<List<&2, String>>:
        found : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind(path)
        first : List<&2, String> <- pathFiles(path, kind, found)
        later : List<&2, String> <- collectFilesFromPaths(rest, kind)
        return List.append(&2, String, first, later)

# Accumulation
# ------------

def hasResource(resources: List<&2, ResolvedResource>, +path: String) -> Bool:
  match resources:
    case Nil{}: False{}
    case ResolvedResource{known, _, _} <> rest: String.eq(known, path) || hasResource(rest, path)

# Insertion order is kept; the first metadata for a path wins.
def added(+resources: List<&2, ResolvedResource>, +path: String, metadata: PathMetadata, enabled: Bool) -> List<&2, ResolvedResource>:
  Bool.pick(List<&2, ResolvedResource>, String.is_empty(path) || hasResource(resources, path), resources, List.append(&2, ResolvedResource, resources, ResolvedResource{path, enabled, metadata} <> Nil{}))


def addedAll(paths: List<&2, String>, resources: List<&2, ResolvedResource>, +metadata: PathMetadata, +enabledPaths: List<&2, String>) -> List<&2, ResolvedResource>:
  match paths:
    case Nil{}: resources
    case +path <> rest: addedAll(rest, added(resources, path, metadata, listed(enabledPaths, path)), metadata, enabledPaths)

def addedOverridden(paths: List<&2, String>, resources: List<&2, ResolvedResource>, +metadata: PathMetadata, +overrides: List<&2, String>, +baseDir: String) -> List<&2, ResolvedResource>:
  match paths:
    case Nil{}: resources
    case +path <> rest: addedOverridden(rest, added(resources, path, metadata, isEnabledByOverrides(path, overrides, baseDir)), metadata, overrides, baseDir)

def resolvedFrom(+environment: Paths.Environment, entries: List<&2, String>, +baseDir: String) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> +rest:
      Result.default(&2, &2, Paths.Error, List<&2, String>, Result.map(&2, &2, Paths.Error, String, List<&2, String>, path => path <> resolvedFrom(environment, rest, baseDir), Paths.resolvePath(environment, entry, baseDir, Paths.PathInputOptions{True{}, True{}, None{}, False{}, False{}})), resolvedFrom(environment, rest, baseDir))

def plainEntries(entries: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = plainEntries(rest)
      Bool.pick(List<&2, String>, isPattern(entry), tail, entry <> tail)

def patternEntries(entries: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = patternEntries(rest)
      Bool.pick(List<&2, String>, isPattern(entry), entry <> tail, tail)

# upstream resolveLocalEntries: plain entries name files or directories to
# search; patterns select which of those are enabled.
def resolveLocalEntries(+environment: Paths.Environment, +entries: List<&2, String>, kind: ResourceType, resources: List<&2, ResolvedResource>, metadata: PathMetadata, +baseDir: String) -> IO(List<&2, ResolvedResource>):
  match entries:
    case Nil{}: IO.pure(List<&2, ResolvedResource>, resources)
    case _:
      do IO<List<&2, ResolvedResource>>:
        +files : List<&2, String> <- collectFilesFromPaths(resolvedFrom(environment, plainEntries(entries), baseDir), kind)
        return addedAll(files, resources, metadata, applyPatterns(files, patternEntries(entries), baseDir))

# Settings
# --------

def settingEntries(kind: ResourceType, found: Maybe<&2, Settings.Setting>) -> List<&2, String>:
  match kind found:
    case SkillResources{} Some{Settings.Skills{values}}: values
    case PromptResources{} Some{Settings.Prompts{values}}: values
    case ThemeResources{} Some{Settings.Themes{values}}: values
    case _ _: Nil{}

def settingName(kind: ResourceType) -> String:
  match kind:
    case SkillResources{}: "skills"
    case PromptResources{}: "prompts"
    case ThemeResources{}: "themes"

def entriesIn(settings: Settings.Settings, +kind: ResourceType) -> List<&2, String>:
  settingEntries(kind, Settings.get(settings, settingName(kind)))

type Context is Data:
  Context{environment: Paths.Environment, settings: Settings.SettingsManager, cwd: String, agentDir: String, home: String}

def projectEntries(context: Context, kind: ResourceType) -> List<&2, String>:
  match context:
    case Context{_, settings, _, _, _}: entriesIn(Settings.getProjectSettings(settings), kind)

def globalEntries(context: Context, kind: ResourceType) -> List<&2, String>:
  match context:
    case Context{_, settings, _, _, _}: entriesIn(Settings.getGlobalSettings(settings), kind)

def projectBase(context: Context) -> String:
  match context:
    case Context{_, _, cwd, _, _}: Path.join(cwd, ".pi")

def globalBase(context: Context) -> String:
  match context:
    case Context{_, _, _, agentDir, _}: agentDir

def environmentOf(context: Context) -> Paths.Environment:
  match context:
    case Context{environment, _, _, _, _}: environment

def trusted(context: Context) -> Bool:
  match context:
    case Context{_, settings, _, _, _}: Settings.isProjectTrusted(settings)

def localResources(+context: Context, +kind: ResourceType) -> IO(List<&2, ResolvedResource>):
  do IO<List<&2, ResolvedResource>>:
    project : List<&2, ResolvedResource> <- resolveLocalEntries(environmentOf(context), projectEntries(context, kind), kind, Nil{}, PathMetadata{Local{}, ProjectScope{}, None{}}, projectBase(context))
    resolveLocalEntries(environmentOf(context), globalEntries(context, kind), kind, project, PathMetadata{Local{}, UserScope{}, None{}}, globalBase(context))

# upstream collectAncestorAgentsSkillDirs: .agents/skills in the cwd and each
# ancestor up to the Git root (or the filesystem root).
def atRoot(gitRoot: Maybe<&2, String>, dir: String) -> Bool:
  match gitRoot:
    case None{}: False{}
    case Some{root}: String.eq(root, dir)

def agentsDirOf(dir: String, reversed: List<&2, String>) -> List<&2, String>: Path.join(dir, ".agents/skills") <> reversed

def ancestorAgentsDirs(fuel: Nat, +dir: String, +gitRoot: Maybe<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: List.reverse(&2, String, Path.join(dir, ".agents/skills") <> reversed)
    case 1n+rest:
      +parent = Skills.parent(dir)
      +next = agentsDirOf(dir, reversed)
      Bool.pick(Unit -> List<&2, String>, atRoot(gitRoot, dir) || String.eq(parent, dir) || String.is_empty(parent), _ => List.reverse(&2, String, next), _ => ancestorAgentsDirs(rest, parent, gitRoot, next))(Unit{})

def gitRootFrom(fuel: Nat, +dir: String) -> IO(Maybe<&2, String>):
  match fuel:
    case 0n: IO.pure(Maybe<&2, String>, None{})
    case 1n+rest:
      do IO<Maybe<&2, String>>:
        present : Bool <- exists(Path.join(dir, ".git"))
        +parent : String = Skills.parent(dir)
        Bool.pick(Unit -> IO(Maybe<&2, String>), present,
          _ => IO.pure(Maybe<&2, String>, Some{dir}),
          _ => Bool.pick(Unit -> IO(Maybe<&2, String>), String.eq(parent, dir) || String.is_empty(parent), _ => IO.pure(Maybe<&2, String>, None{}), _ => gitRootFrom(rest, parent))(Unit{}))(Unit{})

def homeOf(context: Context) -> String:
  match context:
    case Context{_, _, _, _, home}: home

def cwdOf(context: Context) -> String:
  match context:
    case Context{_, _, cwd, _, _}: cwd

def autoMetadata(scope: Scope, baseDir: String) -> PathMetadata: PathMetadata{Auto{}, scope, Some{baseDir}}

def addedAuto(+resources: List<&2, ResolvedResource>, +paths: List<&2, String>, scope: Scope, +overrides: List<&2, String>, +baseDir: String) -> List<&2, ResolvedResource>:
  addedOverridden(paths, resources, autoMetadata(scope, baseDir), overrides, baseDir)

def whenTrusted(trusted: Bool, found: IO(List<&2, String>)) -> IO(List<&2, String>):
  match trusted:
    case True{}: found
    case False{}: IO.pure(List<&2, String>, Nil{})

def canonical(+path: String) -> IO(String):
  do IO<String>:
    real : Result<&2, &2, FS.Error, String> <- FS.realpath(path)
    return Result.default(&2, &2, FS.Error, String, real, path)

def withoutPath(dirs: List<&2, String>, +excluded: String) -> List<&2, String>:
  match dirs:
    case Nil{}: Nil{}
    case +dir <> rest:
      +tail = withoutPath(rest, excluded)
      Bool.pick(List<&2, String>, String.eq(Path.normalize(dir), excluded), tail, dir <> tail)

# Project .agents skill directories, each its own base directory.
def addedAgentsDirs(dirs: List<&2, String>, +resources: List<&2, ResolvedResource>, +overrides: List<&2, String>) -> IO(List<&2, ResolvedResource>):
  match dirs:
    case Nil{}: IO.pure(List<&2, ResolvedResource>, resources)
    case +dir <> rest:
      do IO<List<&2, ResolvedResource>>:
        found : List<&2, String> <- collectSkillEntries(dir, AgentsSkills{})
        addedAgentsDirs(rest, addedAuto(resources, found, ProjectScope{}, overrides, Skills.parent(dir)), overrides)

def projectAgentsDirs(+context: Context) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    +cwd : String <- IO.pure(String, Path.normalize(cwdOf(context)))
    gitRoot : Maybe<&2, String> <- gitRootFrom(4096n, cwd)
    return Bool.pick(List<&2, String>, trusted(context), withoutPath(ancestorAgentsDirs(4096n, cwd, gitRoot, Nil{}), Path.normalize(Path.join(homeOf(context), ".agents/skills"))), Nil{})

# upstream addAutoDiscoveredResources, skills: project .pi (trusted), project
# .agents ancestors, user agent directory, then ~/.agents.
def autoSkills(+context: Context, +resources: List<&2, ResolvedResource>) -> IO(List<&2, ResolvedResource>):
  +projectOverrides = projectEntries(context, SkillResources{})
  +userOverrides = globalEntries(context, SkillResources{})
  +userAgents = Path.join(homeOf(context), ".agents/skills")
  do IO<List<&2, ResolvedResource>>:
    project : List<&2, String> <- whenTrusted(trusted(context), collectSkillEntries(Path.join(projectBase(context), "skills"), PiSkills{}))
    agentsDirs : List<&2, String> <- projectAgentsDirs(context)
    withAgents : List<&2, ResolvedResource> <- addedAgentsDirs(agentsDirs, addedAuto(resources, project, ProjectScope{}, projectOverrides, projectBase(context)), projectOverrides)
    user : List<&2, String> <- collectSkillEntries(Path.join(globalBase(context), "skills"), PiSkills{})
    userAgentSkills : List<&2, String> <- collectSkillEntries(userAgents, AgentsSkills{})
    return addedAuto(addedAuto(withAgents, user, UserScope{}, userOverrides, globalBase(context)), userAgentSkills, UserScope{}, userOverrides, Skills.parent(userAgents))

# Prompts and themes: the project's own directory when trusted, then the user's.
def autoFiles(+context: Context, +kind: ResourceType, +resources: List<&2, ResolvedResource>) -> IO(List<&2, ResolvedResource>):
  +folder = settingName(kind)
  do IO<List<&2, ResolvedResource>>:
    project : List<&2, String> <- whenTrusted(trusted(context), collectAutoEntries(Path.join(projectBase(context), folder), extensionOf(kind)))
    user : List<&2, String> <- collectAutoEntries(Path.join(globalBase(context), folder), extensionOf(kind))
    return addedAuto(addedAuto(resources, project, ProjectScope{}, projectEntries(context, kind), projectBase(context)), user, UserScope{}, globalEntries(context, kind), globalBase(context))

def rank(resource: ResolvedResource) -> Nat:
  match resource:
    case ResolvedResource{_, _, PathMetadata{Local{}, ProjectScope{}, _}}: 0n
    case ResolvedResource{_, _, PathMetadata{Auto{}, ProjectScope{}, _}}: 1n
    case ResolvedResource{_, _, PathMetadata{Local{}, UserScope{}, _}}: 2n
    case ResolvedResource{_, _, PathMetadata{Auto{}, UserScope{}, _}}: 3n

def rankedBefore(left: ResolvedResource, right: ResolvedResource) -> Bool: Nat.is_le(rank(left), rank(right))

def pathOf(resource: ResolvedResource) -> String:
  match resource:
    case ResolvedResource{path, _, _}: path

def deduplicated(resources: List<&2, ResolvedResource>, +seen: List<&2, String>) -> IO(List<&2, ResolvedResource>):
  match resources:
    case Nil{}: IO.pure(List<&2, ResolvedResource>, Nil{})
    case +resource <> +rest:
      do IO<List<&2, ResolvedResource>>:
        +real : String <- canonical(pathOf(resource))
        Bool.pick(Unit -> IO(List<&2, ResolvedResource>), listed(seen, real),
          _ => deduplicated(rest, seen),
          _ => do IO<List<&2, ResolvedResource>>:
            later : List<&2, ResolvedResource> <- deduplicated(rest, real <> seen)
            return resource <> later)(Unit{})

# upstream toResolvedPaths: a stable sort by precedence (project before user,
# local before auto), then the first of each canonical path.
def toResolved(+resources: List<&2, ResolvedResource>) -> IO(List<&2, ResolvedResource>):
  deduplicated(Sort.sort(~ResolvedResource, ~rankedBefore, resources), Nil{})

def autoFor(+context: Context, +kind: ResourceType, +resources: List<&2, ResolvedResource>) -> IO(List<&2, ResolvedResource>):
  match kind:
    case SkillResources{}: autoSkills(context, resources)
    case _: autoFiles(context, kind, resources)

def resolvedType(+context: Context, +kind: ResourceType) -> IO(List<&2, ResolvedResource>):
  do IO<List<&2, ResolvedResource>>:
    local : List<&2, ResolvedResource> <- localResources(context, kind)
    all : List<&2, ResolvedResource> <- autoFor(context, kind, local)
    toResolved(all)

# upstream PackageManager.resolve (without package sources).
def contextOf(environment: Paths.Environment, settings: Settings.SettingsManager, cwd: String, agentDir: String) -> Context:
  match environment:
    case Paths.Environment{processCwd, +home, url}: Context{Paths.Environment{processCwd, home, url}, settings, cwd, agentDir, home}

def resolvedIn(+context: Context) -> IO(ResolvedPaths):
  do IO<ResolvedPaths>:
    skills : List<&2, ResolvedResource> <- resolvedType(context, SkillResources{})
    prompts : List<&2, ResolvedResource> <- resolvedType(context, PromptResources{})
    themes : List<&2, ResolvedResource> <- resolvedType(context, ThemeResources{})
    return ResolvedPaths{skills, prompts, themes}

# upstream PackageManager.resolve (without package sources).
def resolve(environment: Paths.Environment, settings: Settings.SettingsManager, cwd: String, agentDir: String) -> IO(ResolvedPaths):
  resolvedIn(contextOf(environment, settings, cwd, agentDir))

def enabledPaths(resources: List<&2, ResolvedResource>) -> List<&2, String>:
  match resources:
    case Nil{}: Nil{}
    case ResolvedResource{path, True{}, _} <> rest: path <> enabledPaths(rest)
    case _ <> rest: enabledPaths(rest)

# Package sources
# ---------------
# upstream parseSource, getPackageIdentity, settings source normalization
# and install locations. Installing, updating and resolving package contents
# (npm and git commands, manifests, filters) are not ported yet.

# upstream NpmSource (without `range`, which needs semver ranges), GitSource
# and LocalSource.
type ParsedSource is Data:
  NpmSource{spec: String, name: String, version: Maybe<&2, String>, pinned: Bool}
  GitRepo{git: Git.GitSource}
  LocalSource{path: String}

# upstream SourceScope (the metadata `Scope` is its non-temporary part).
type SourceScope is Data:
  UserSource{}
  ProjectSource{}
  TemporarySource{}

type NpmSpec is Data:
  NpmSpec{name: String, version: Maybe<&2, String>}

def lineTerminator(+code: U32) -> Bool:
  U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

def singleLine(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: Bool.not(lineTerminator(code)) && singleLine(rest)

def specParts(+spec: String, +lead: String, text: String, +reversed: String) -> NpmSpec:
  match text:
    case SNil{}: Bool.pick(NpmSpec, String.is_empty(reversed), NpmSpec{spec, None{}}, NpmSpec{lead ++ String.reverse(reversed), None{}})
    case SCon{'@', +version}: Bool.pick(NpmSpec, Bool.not(String.is_empty(reversed)) && Bool.not(String.is_empty(version)) && singleLine(version), NpmSpec{lead ++ String.reverse(reversed), Some{version}}, NpmSpec{spec, None{}})
    case SCon{char, rest}: specParts(spec, lead, rest, SCon{char, reversed})

# /^(@?[^@]+(?:\/[^@]+)?)(?:@(.+))?$/: the name up to the first @ after an
# optional scope @, then a non-empty single-line version; else the whole spec.
def parseNpmSpec(+spec: String) -> NpmSpec:
  match spec:
    case SCon{'@', rest}: specParts(spec, "@", rest, "")
    case other: specParts(spec, "", other, "")

# upstream isExactNpmVersion: semver's valid(version ?? "").
def isExactNpmVersion(version: Maybe<&2, String>) -> Bool: Maybe.is_some(&2, String, Semver.valid(Maybe.default(&2, String, version, "")))

def npmSource(+spec: String, parsed: NpmSpec) -> ParsedSource:
  match parsed:
    case NpmSpec{name, +version}: NpmSource{spec, name, version, isExactNpmVersion(version)}

def gitOrLocal(+source: String, parsed: Maybe<&2, Git.GitSource>) -> ParsedSource:
  match parsed:
    case Some{git}: GitRepo{git}
    case None{}: LocalSource{source}

def urlContextOf(context: Context) -> URL.Context:
  match context:
    case Context{Paths.Environment{_, _, url}, _, _, _, _}: url

# upstream parseSource: npm:, then a local path, then a git URL, else local.
def parseSource(+context: Context, +source: String) -> ParsedSource:
  Bool.pick(Unit -> ParsedSource, String.starts_with(source, "npm:"),
    _ => npmSource(Text.trim(String.drop(source, 4n)), parseNpmSpec(Text.trim(String.drop(source, 4n)))),
    _ => Bool.pick(Unit -> ParsedSource, Paths.isLocalPath(source), _ => LocalSource{source}, _ => gitOrLocal(source, Git.parseGitUrl(urlContextOf(context), source)))(Unit{}))(Unit{})

def PROJECT_UNTRUSTED() -> String: "Project is not trusted; refusing to access project package storage"

# upstream getBaseDirForScope: the project's .pi (trusted only), the agent
# directory, or the working directory for temporary sources.
def baseDirForScope(+context: Context, scope: SourceScope) -> Result<&2, &2, String, String>:
  match scope:
    case ProjectSource{}: Bool.pick(Result<&2, &2, String, String>, trusted(context), Done{projectBase(context)}, Fail{PROJECT_UNTRUSTED()})
    case UserSource{}: Done{globalBase(context)}
    case TemporarySource{}: Done{cwdOf(context)}

# upstream resolvePathFromBase: trimmed, with ~ as the home directory.
def resolvePathFromBase(+context: Context, +input: String, baseDir: String) -> String:
  Result.default(&2, &2, Paths.Error, String, Paths.resolvePath(environmentOf(context), input, baseDir, Paths.PathInputOptions{True{}, True{}, Some{homeOf(context)}, False{}, False{}}), input)

def resolveSourcePath(+context: Context, input: String) -> String: resolvePathFromBase(context, input, cwdOf(context))

def npmIdentity(parsed: ParsedSource) -> Maybe<&2, String>:
  match parsed:
    case NpmSource{_, name, _, _}: Some{"npm:" ++ name}
    case GitRepo{Git.GitSource{_, host, path, _, _}}: Some{"git:" ++ host ++ "/" ++ path}
    case LocalSource{_}: None{}

def localPathOf(parsed: ParsedSource) -> String:
  match parsed:
    case LocalSource{path}: path
    case _: ""

def localKey(+context: Context, +parsed: ParsedSource, base: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  Result.map(&2, &2, String, String, String, baseDir => "local:" ++ resolvePathFromBase(context, localPathOf(parsed), baseDir), base)

# upstream getPackageIdentity: npm:<name>, git:<host>/<path>, or the local
# path resolved against the scope's base (the working directory without one).
def identityOf(+context: Context, +parsed: ParsedSource, remote: Maybe<&2, String>, scope: Maybe<&2, SourceScope>) -> Result<&2, &2, String, String>:
  match remote scope:
    case Some{identity} _: Done{identity}
    case None{} Some{given}: localKey(context, parsed, baseDirForScope(context, given))
    case None{} None{}: Done{"local:" ++ resolveSourcePath(context, localPathOf(parsed))}

def getPackageIdentity(+context: Context, +source: String, scope: Maybe<&2, SourceScope>) -> Result<&2, &2, String, String>:
  +parsed = parseSource(context, source)
  identityOf(context, parsed, npmIdentity(parsed), scope)

def inputKey(+context: Context, +source: String) -> String:
  Result.default(&2, &2, String, String, getPackageIdentity(context, source, None{}), "")

def sourceString(pkg: Settings.PackageSource) -> String:
  match pkg:
    case Settings.PackageName{source}: source
    case Settings.FilteredPackage{source, _, _}: source

def withSource(pkg: Settings.PackageSource, source: String) -> Settings.PackageSource:
  match pkg:
    case Settings.PackageName{_}: Settings.PackageName{source}
    case Settings.FilteredPackage{_, filter, unknown}: Settings.FilteredPackage{source, filter, unknown}

# upstream packageSourcesMatch: the settings entry keyed in its scope, the
# input keyed from the working directory.
def sourcesMatch(+context: Context, +scope: SourceScope, existing: Settings.PackageSource, +inputKey: String) -> Result<&2, &2, String, Bool>:
  Result.map(&2, &2, String, String, Bool, key => String.eq(key, inputKey), getPackageIdentity(context, sourceString(existing), Some{scope}))

def nonEmptyOr(text: String, +fallback: String) -> String:
  match text:
    case SNil{}: fallback
    case other: other

# upstream normalizePackageSourceForSettings: a local path relative to the
# scope's base directory ("." for the base itself); other sources unchanged.
def normalizeLocal(+context: Context, +path: String, base: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  Result.map(&2, &2, String, String, String, baseDir => nonEmptyOr(Path.relative(baseDir, resolveSourcePath(context, path)), "."), base)

def normalizedParsed(+context: Context, +source: String, +scope: SourceScope, parsed: ParsedSource) -> Result<&2, &2, String, String>:
  match parsed:
    case LocalSource{path}: normalizeLocal(context, path, baseDirForScope(context, scope))
    case _: Done{source}

def normalizePackageSourceForSettings(+context: Context, +source: String, +scope: SourceScope) -> Result<&2, &2, String, String>:
  normalizedParsed(context, source, scope, parseSource(context, source))

def scopeOf(local: Bool) -> SourceScope: Bool.pick(SourceScope, local, ProjectSource{}, UserSource{})

def settingsFor(context: Context, scope: SourceScope) -> Settings.Settings:
  match context scope:
    case Context{_, settings, _, _, _} ProjectSource{}: Settings.getProjectSettings(settings)
    case Context{_, settings, _, _, _} _: Settings.getGlobalSettings(settings)

def packagesIn(settings: Settings.Settings) -> List<&2, Settings.PackageSource>:
  Maybe.default(&2, List<&2, Settings.PackageSource>, Settings.selectedPackages(Settings.get(settings, "packages")), Nil{})

def settingsError(error: Settings.Error) -> String: Diagnostics.settingsErrorText(error)

def withSettings(context: Context, result: Result<&2, &2, Settings.Error, Settings.SettingsManager>) -> Result<&2, &2, String, Context>:
  match context result:
    case _ Fail{error}: Fail{settingsError(error)}
    case Context{environment, _, cwd, agentDir, home} Done{settings}: Done{Context{environment, settings, cwd, agentDir, home}}

def storedPackages(+context: Context, scope: SourceScope, packages: List<&2, Settings.PackageSource>) -> Result<&2, &2, String, Context>:
  match context scope:
    case Context{_, settings, _, _, _} ProjectSource{}: withSettings(context, Settings.setProjectPackages(packages, settings))
    case Context{_, settings, _, _, _} _: withSettings(context, Settings.setPackages(packages, settings))

# The settings after an add or remove, and whether they changed.
type SettingsChange is Data:
  SettingsChange{changed: Bool, context: Context}

def unchanged(context: Context) -> Result<&2, &2, String, SettingsChange>: Done{SettingsChange{False{}, context}}

def changedWith(result: Result<&2, &2, String, Context>) -> Result<&2, &2, String, SettingsChange>:
  Result.map(&2, &2, String, Context, SettingsChange, next => SettingsChange{True{}, next}, result)

type Located is Data:
  Located{index: Maybe<&2, Nat>, failure: Maybe<&2, String>}

def matchResults(+context: Context, +scope: SourceScope, packages: List<&2, Settings.PackageSource>, +inputKey: String) -> List<&2, Result<&2, &2, String, Bool>>:
  match packages:
    case Nil{}: Nil{}
    case pkg <> rest: sourcesMatch(context, scope, pkg, inputKey) <> matchResults(context, scope, rest, inputKey)

# The first matching entry; a scope failure (an untrusted project) stops.
def located(results: List<&2, Result<&2, &2, String, Bool>>, +index: Nat) -> Located:
  match results:
    case Nil{}: Located{None{}, None{}}
    case Fail{message} <> _: Located{None{}, Some{message}}
    case Done{True{}} <> _: Located{Some{index}, None{}}
    case Done{False{}} <> rest: located(rest, 1n+index)

def replacedAt(packages: List<&2, Settings.PackageSource>, index: Nat, +source: String) -> List<&2, Settings.PackageSource>:
  match packages index:
    case Nil{} _: Nil{}
    case pkg <> rest 0n: withSource(pkg, source) <> rest
    case pkg <> rest 1n+previous: pkg <> replacedAt(rest, previous, source)

def sourceAt(packages: List<&2, Settings.PackageSource>, index: Nat) -> String:
  match packages index:
    case Nil{} _: ""
    case pkg <> _ 0n: sourceString(pkg)
    case _ <> rest 1n+previous: sourceAt(rest, previous)

def addNormalized(+context: Context, +scope: SourceScope, +packages: List<&2, Settings.PackageSource>, +normalized: String, found: Located) -> Result<&2, &2, String, SettingsChange>:
  match found:
    case Located{_, Some{message}}: Fail{message}
    case Located{Some{+index}, None{}}: Bool.pick(Unit -> Result<&2, &2, String, SettingsChange>, String.eq(sourceAt(packages, index), normalized), _ => unchanged(context), _ => changedWith(storedPackages(context, scope, replacedAt(packages, index, normalized))))(Unit{})
    case Located{None{}, None{}}: changedWith(storedPackages(context, scope, List.append(&2, Settings.PackageSource, packages, [Settings.PackageName{normalized}])))

def addWith(+context: Context, +source: String, +scope: SourceScope, normalized: Result<&2, &2, String, String>) -> Result<&2, &2, String, SettingsChange>:
  match normalized:
    case Fail{message}: Fail{message}
    case Done{+value}:
      +packages = packagesIn(settingsFor(context, scope))
      addNormalized(context, scope, packages, value, located(matchResults(context, scope, packages, inputKey(context, source)), 0n))

# upstream addSourceToSettings: add the normalized source to the user's (or,
# with local, the project's) packages, or replace the ref of the entry for
# the same package, keeping its filters. Unchanged when it is already there.
def addSourceToSettings(+context: Context, +source: String, +local: Bool) -> Result<&2, &2, String, SettingsChange>:
  addWith(context, source, scopeOf(local), normalizePackageSourceForSettings(context, source, scopeOf(local)))

def kept(results: List<&2, Result<&2, &2, String, Bool>>, packages: List<&2, Settings.PackageSource>) -> Result<&2, &2, String, List<&2, Settings.PackageSource>>:
  match results packages:
    case Fail{message} <> _ _: Fail{message}
    case Done{True{}} <> rest _ <> more: kept(rest, more)
    case Done{False{}} <> rest pkg <> more: Result.map(&2, &2, String, List<&2, Settings.PackageSource>, List<&2, Settings.PackageSource>, tail => pkg <> tail, kept(rest, more))
    case _ _: Done{Nil{}}

def removedFrom(+context: Context, +scope: SourceScope, +before: Nat, remaining: Result<&2, &2, String, List<&2, Settings.PackageSource>>) -> Result<&2, &2, String, SettingsChange>:
  match remaining:
    case Fail{message}: Fail{message}
    case Done{+packages}: Bool.pick(Unit -> Result<&2, &2, String, SettingsChange>, Nat.is_eq(List.length(&2, Settings.PackageSource, packages), before), _ => unchanged(context), _ => changedWith(storedPackages(context, scope, packages)))(Unit{})

# upstream removeSourceFromSettings: drop every entry for the same package.
def removeSourceFromSettings(+context: Context, +source: String, local: Bool) -> Result<&2, &2, String, SettingsChange>:
  +scope = scopeOf(local)
  +packages = packagesIn(settingsFor(context, scope))
  removedFrom(context, scope, List.length(&2, Settings.PackageSource, packages), kept(matchResults(context, scope, packages, inputKey(context, source)), packages))

# Install locations
# -----------------

# upstream resolveManagedPath: root/parts resolved as Node's path.resolve,
# refused when it leaves the root.
def resolvedParts(parts: List<&2, String>, +base: String) -> String:
  match parts:
    case Nil{}: base
    case part <> rest: resolvedParts(rest, Maybe.default(&2, String, Path.resolve(base, part), base))

def withTrailingSlash(+path: String) -> String: Bool.pick(String, String.ends_with(path, "/"), path, path ++ "/")

def resolveManagedPath(+root: String, parts: List<&2, String>) -> Result<&2, &2, String, String>:
  +resolvedRoot = Path.normalize(root)
  +resolvedPath = resolvedParts(parts, resolvedRoot)
  Bool.pick(Result<&2, &2, String, String>, String.eq(resolvedPath, resolvedRoot) || String.starts_with(resolvedPath, withTrailingSlash(resolvedRoot)), Done{resolvedPath}, Fail{"Refusing to use path outside package install root: " ++ resolvedPath})

# upstream getExtensionTempFolder: <agentDir>/tmp/extensions, created with
# mode 0700.
def getExtensionTempFolder(+agentDir: String) -> IO(String):
  +folder = Path.join(agentDir, "tmp/extensions")
  do IO<String>:
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(folder)
    moded : Result<&2, &2, FS.Error, Unit> <- FS.chmod(folder, 448)
    return folder

def hexDigit(+nibble: U32) -> Char: Chr{Bool.pick(U32, U32.is_lt(nibble, 10), (48 + nibble : U32), (87 + nibble : U32))}

def hexBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest: SCon{hexDigit((byte >> 4n : U32)), SCon{hexDigit((byte .&. 15 : U32)), hexBytes(rest)}}

def digestHex(result: Result<&2, &2, Sha256.Error, Sha256.Digest>) -> String:
  match result:
    case Done{digest}: hexBytes(Sha256.toBytes(digest))
    case Fail{_}: ""

# upstream getTemporaryDir: the prefix folder under the temporary extension
# folder, then the first 8 hex digits of sha256("<prefix>-<suffix>").
def temporaryUnder(+prefix: String, +suffix: String, root: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  Result.bind(&2, &2, String, String, String, root, base => resolveManagedPath(base, [String.take(digestHex(Sha256.digest(Utf8.encode(prefix ++ "-" ++ suffix))), 8n), suffix]))

def getTemporaryDir(+context: Context, +prefix: String, +suffix: String) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    folder : String <- getExtensionTempFolder(globalBase(context))
    return temporaryUnder(prefix, suffix, resolveManagedPath(folder, [prefix]))

def gitInstallRoot(+context: Context, scope: SourceScope) -> Result<&2, &2, String, String>:
  match scope:
    case ProjectSource{}: Bool.pick(Result<&2, &2, String, String>, trusted(context), Done{Path.join(projectBase(context), "git")}, Fail{PROJECT_UNTRUSTED()})
    case _: Done{Path.join(globalBase(context), "git")}

# upstream getGitInstallPath: <root>/<host>/<path> under the scope's git
# root, or a temporary folder.
def getGitInstallPath(+context: Context, source: Git.GitSource, scope: SourceScope) -> IO(Result<&2, &2, String, String>):
  match source scope:
    case Git.GitSource{_, +host, path, _, _} TemporarySource{}: getTemporaryDir(context, "git-" ++ host, path)
    case Git.GitSource{_, host, path, _, _} _: IO.pure(Result<&2, &2, String, String>, Result.bind(&2, &2, String, String, String, gitInstallRoot(context, scope), root => resolveManagedPath(root, [host, path])))

def npmPackageUnder(+name: String, root: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  Result.map(&2, &2, String, String, String, base => Path.join(Path.join(base, "node_modules"), name), root)

# upstream getManagedNpmInstallPath: node_modules/<name> under the scope's
# npm root, or under a temporary folder.
def getManagedNpmInstallPath(+context: Context, +name: String, scope: SourceScope) -> IO(Result<&2, &2, String, String>):
  match scope:
    case TemporarySource{}:
      do IO<Result<&2, &2, String, String>>:
        root : Result<&2, &2, String, String> <- getTemporaryDir(context, "npm", "")
        return npmPackageUnder(name, root)
    case ProjectSource{}: IO.pure(Result<&2, &2, String, String>, npmPackageUnder(name, Bool.pick(Result<&2, &2, String, String>, trusted(context), Done{Path.join(projectBase(context), "npm")}, Fail{PROJECT_UNTRUSTED()})))
    case UserSource{}: IO.pure(Result<&2, &2, String, String>, npmPackageUnder(name, Done{Path.join(globalBase(context), "npm")}))
