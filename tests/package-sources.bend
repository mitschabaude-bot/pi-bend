import Base
import ../packages/coding-agent/src/core/package-manager.bend as PM
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/utils/git.bend as Git
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ./loopback-fetch.bend as Loop

# upstream packages/coding-agent/test/package-manager-ssh.test.ts and the
# source-management blocks of package-manager.test.ts ("source parsing",
# "git install paths", "temporary install paths", "settings source
# normalization", "HTTPS git URL parsing (old behavior)"). Private methods the
# upstream tests reach through `as any` are this module's functions; the
# manager state is PM.Context over an in-memory SettingsManager. Args: a fresh
# temporary directory (upstream's tempDir) and a home directory; a first run
# with only these creates the temporary extension folder, and
# tests/package_sources_check.py passes its mode to the second run.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def contextOf(+tempDir: String, +home: String, settings: Settings.SettingsManager) -> PM.Context:
  PM.Context{Paths.Environment{tempDir, home, Loop.urlContext()}, settings, tempDir, Path.join(tempDir, "agent"), home}

def managerOf(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def fresh(+tempDir: String, +home: String) -> IO(PM.Context):
  do IO<PM.Context>:
    pair : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(), Settings.options())
    return contextOf(tempDir, home, managerOf(pair))

def gitOf(parsed: PM.ParsedSource) -> Maybe<&2, Git.GitSource>:
  match parsed:
    case PM.GitRepo{git}: Some{git}
    case _: None{}

def isGit(parsed: PM.ParsedSource) -> Bool: Maybe.is_some(&2, Git.GitSource, gitOf(parsed))

def isLocal(parsed: PM.ParsedSource, +path: Maybe<&2, String>) -> Bool:
  match parsed path:
    case PM.LocalSource{found} Some{wanted}: String.eq(found, wanted)
    case PM.LocalSource{_} None{}: True{}
    case _ _: False{}

def pinnedNpm(parsed: PM.ParsedSource) -> Maybe<&2, Bool>:
  match parsed:
    case PM.NpmSource{_, _, _, pinned}: Some{pinned}
    case _: None{}

def sameMaybe(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def gitFields(git: Maybe<&2, Git.GitSource>, +host: String, +path: String, repo: Maybe<&2, String>, ref: Maybe<&2, Maybe<&2, String>>, pinned: Maybe<&2, Bool>) -> Bool:
  match git:
    case Some{Git.GitSource{r, h, p, found, +isPinned}}:
      String.eq(h, host) && String.eq(p, path) && Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, wanted => String.eq(r, wanted), repo), True{}) && Maybe.default(&2, Bool, Maybe.map(&2, Maybe<&2, String>, Bool, wanted => sameMaybe(found, wanted), ref), True{}) && Maybe.default(&2, Bool, Maybe.map(&2, Bool, Bool, wanted => Bool.not(Bool.xor(isPinned, wanted)), pinned), True{})
    case None{}: False{}

# The fields a test names: host and path always; repo, ref and pinned when given.
def gitIs(parsed: PM.ParsedSource, +host: String, +path: String, repo: Maybe<&2, String>, ref: Maybe<&2, Maybe<&2, String>>, pinned: Maybe<&2, Bool>) -> Bool:
  gitFields(gitOf(parsed), host, path, repo, ref, pinned)

def identityIs(result: Result<&2, &2, String, String>, +expected: String) -> Bool:
  match result:
    case Done{value}: String.eq(value, expected)
    case Fail{_}: False{}

def identity(+c: PM.Context, +source: String) -> Result<&2, &2, String, String>: PM.getPackageIdentity(c, source, None{})

# package-manager-ssh.test.ts
def sshCases(+c: PM.Context) -> IO(Unit):
  do IO<Unit>:
    check(gitIs(PM.parseSource(c, "https://github.com/user/repo"), "github.com", "user/repo", None{}, None{}, None{}), "Package Manager git source parsing protocol URLs without git: prefix should parse https:// URL")
    check(gitIs(PM.parseSource(c, "ssh://git@github.com/user/repo"), "github.com", "user/repo", Some{"ssh://git@github.com/user/repo"}, None{}, None{}), "Package Manager git source parsing protocol URLs without git: prefix should parse ssh:// URL")
    check(gitIs(PM.parseSource(c, "git:git@github.com:user/repo"), "github.com", "user/repo", Some{"git@github.com:user/repo"}, None{}, Some{False{}}), "Package Manager git source parsing shorthand URLs with git: prefix should parse git@host:path format")
    check(gitIs(PM.parseSource(c, "git:github.com/user/repo"), "github.com", "user/repo", None{}, None{}, None{}), "Package Manager git source parsing shorthand URLs with git: prefix should parse host/path shorthand")
    check(gitIs(PM.parseSource(c, "git:git@github.com:user/repo@v1.0.0"), "github.com", "user/repo", None{}, Some{Some{"v1.0.0"}}, Some{True{}}), "Package Manager git source parsing shorthand URLs with git: prefix should parse shorthand with ref")
    check(isLocal(PM.parseSource(c, "git@github.com:user/repo"), None{}), "Package Manager git source parsing unsupported without git: prefix should treat git@host:path as local without git: prefix")
    check(isLocal(PM.parseSource(c, "github.com/user/repo"), None{}), "Package Manager git source parsing unsupported without git: prefix should treat host/path shorthand as local without git: prefix")
    check(identityIs(identity(c, "git:git@github.com:user/repo"), "git:github.com/user/repo") && identityIs(identity(c, "https://github.com/user/repo"), "git:github.com/user/repo") && identityIs(identity(c, "ssh://git@github.com/user/repo"), "git:github.com/user/repo"), "Package Manager git source parsing identity normalization should normalize protocol and shorthand-prefixed URLs to same identity")

def sourceParsing(+c: PM.Context) -> IO(Unit):
  do IO<Unit>:
    check(Maybe.default(&2, Bool, pinnedNpm(PM.parseSource(c, "npm:@scope/pkg@1.2.3")), False{}) && Bool.not(Maybe.default(&2, Bool, pinnedNpm(PM.parseSource(c, "npm:@scope/pkg@^1.2.3")), True{})) && Bool.not(Maybe.default(&2, Bool, pinnedNpm(PM.parseSource(c, "npm:pkg")), True{})) && isGit(PM.parseSource(c, "git:github.com/user/repo@v1")) && isGit(PM.parseSource(c, "https://github.com/user/repo@v1")) && isGit(PM.parseSource(c, "git:git@github.com:user/repo@v1")) && isGit(PM.parseSource(c, "ssh://git@github.com/user/repo@v1")) && isLocal(PM.parseSource(c, "/absolute/path/to/package"), None{}) && isLocal(PM.parseSource(c, "./relative/path/to/package"), None{}) && isLocal(PM.parseSource(c, "../relative/path/to/package"), None{}), "DefaultPackageManager source parsing should parse package source types from docs examples")
    check(isLocal(PM.parseSource(c, "./packages/agent-timers"), Some{"./packages/agent-timers"}) && isLocal(PM.parseSource(c, "../packages/agent-timers"), Some{"../packages/agent-timers"}), "DefaultPackageManager source parsing should never parse dot-relative paths as git")

def refused(result: Result<&2, &2, String, String>) -> Bool:
  match result:
    case Fail{message}: String.contains(message, "outside package install root")
    case Done{_}: False{}

def traversalSource() -> Git.GitSource: Git.GitSource{"git@evil.example:../../victim/repo", "evil.example", "../../victim/repo", None{}, False{}}

def gitInstallPaths(+c: PM.Context) -> IO(Unit):
  +traversal = traversalSource()
  do IO<Unit>:
    user : Result<&2, &2, String, String> <- PM.getGitInstallPath(c, traversal, PM.UserSource{})
    project : Result<&2, &2, String, String> <- PM.getGitInstallPath(c, traversal, PM.ProjectSource{})
    temporary : Result<&2, &2, String, String> <- PM.getGitInstallPath(c, traversal, PM.TemporarySource{})
    check(refused(user) && refused(project) && refused(temporary), "DefaultPackageManager git install paths should reject paths outside git install roots")

def underTemp(result: Result<&2, &2, String, String>, +tempRoot: String) -> Bool:
  match result:
    case Done{+path}: String.ends_with(path, "node_modules/left-pad") && Bool.not(String.starts_with(Path.relative(tempRoot, path), "..")) && Bool.not(String.starts_with(path, "/tmp/pi-extensions"))
    case Fail{_}: False{}

def temporaryInstall(+c: PM.Context, +agentDir: String, mode: Maybe<&2, U32>) -> IO(Unit):
  +tempRoot = Path.join(agentDir, "tmp/extensions")
  do IO<Unit>:
    path : Result<&2, &2, String, String> <- PM.getManagedNpmInstallPath(c, "left-pad", PM.TemporarySource{})
    check(underTemp(path, tempRoot) && Maybe.default(&2, Bool, Maybe.map(&2, U32, Bool, value => U32.is_eq(value, 448), mode), False{}), "DefaultPackageManager temporary install paths should place temporary npm packages under the agent temp extension folder")

# The upstream fixture: <dir>/extensions/index.ts.
def packageDir(+dir: String) -> IO(Unit):
  do IO<Unit>:
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(Path.join(dir, "extensions"))
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(Path.join(dir, "extensions/index.ts"), "export default function() {}")
    return Unit{}

def packagesOf(settings: Settings.Settings) -> List<&2, Settings.PackageSource>: PM.packagesIn(settings)

def globalPackages(context: PM.Context) -> List<&2, Settings.PackageSource>:
  match context:
    case PM.Context{_, settings, _, _, _}: packagesOf(Settings.getGlobalSettings(settings))

def projectPackages(context: PM.Context) -> List<&2, Settings.PackageSource>:
  match context:
    case PM.Context{_, settings, _, _, _}: packagesOf(Settings.getProjectSettings(settings))

def onlyName(packages: List<&2, Settings.PackageSource>, +expected: String) -> Bool:
  match packages:
    case Settings.PackageName{source} <> Nil{}: String.eq(source, expected)
    case _: False{}

def dotted(+rel: String) -> String: Bool.pick(String, String.starts_with(rel, "."), rel, "./" ++ rel)

def addResult(~packages: PM.Context -> List<&2, Settings.PackageSource>, result: Result<&2, &2, String, PM.SettingsChange>, +expected: String) -> Bool:
  match result:
    case Done{PM.SettingsChange{True{}, next}}: onlyName(packages(next), expected)
    case _: False{}

def storesGlobal(+c: PM.Context, +tempDir: String) -> IO(Unit):
  +pkgDir = Path.join(tempDir, "packages/local-global-pkg")
  do IO<Unit>:
    packageDir(pkgDir)
    check(addResult(~globalPackages, PM.addSourceToSettings(c, "./packages/local-global-pkg", False{}), dotted(Path.relative(Path.join(tempDir, "agent"), pkgDir))), "DefaultPackageManager settings source normalization should store global local packages relative to agent settings base")

def storesProject(+c: PM.Context, +tempDir: String) -> IO(Unit):
  +pkgDir = Path.join(tempDir, "project-local-pkg")
  do IO<Unit>:
    packageDir(pkgDir)
    check(addResult(~projectPackages, PM.addSourceToSettings(c, "./project-local-pkg", True{}), dotted(Path.relative(Path.join(tempDir, ".pi"), pkgDir))), "DefaultPackageManager settings source normalization should store project local packages relative to .pi settings base")

def removedAll(result: Result<&2, &2, String, PM.SettingsChange>) -> Bool:
  match result:
    case Done{PM.SettingsChange{True{}, next}}: List.is_empty(&2, Settings.PackageSource, globalPackages(next))
    case _: False{}

def removeAfterAdd(+pkgDir: String, result: Result<&2, &2, String, PM.SettingsChange>) -> Bool:
  match result:
    case Done{PM.SettingsChange{_, +next}}: removedAll(PM.removeSourceFromSettings(next, pkgDir ++ "/", False{}))
    case Fail{_}: False{}

def removesEquivalent(+c: PM.Context, +tempDir: String) -> IO(Unit):
  +pkgDir = Path.join(tempDir, "remove-local-pkg")
  do IO<Unit>:
    packageDir(pkgDir)
    check(removeAfterAdd(pkgDir, PM.addSourceToSettings(c, "./remove-local-pkg", False{})), "DefaultPackageManager settings source normalization should remove local package entries using equivalent path forms")

def addedAgain(result: Result<&2, &2, String, PM.SettingsChange>, +expectChange: Bool, +expected: String) -> Bool:
  match result:
    case Done{PM.SettingsChange{flag, next}}: Bool.not(Bool.xor(flag, expectChange)) && onlyName(globalPackages(next), expected)
    case Fail{_}: False{}

def secondAdd(result: Result<&2, &2, String, PM.SettingsChange>, +source: String, +expectChange: Bool, +expected: String) -> Bool:
  match result:
    case Done{PM.SettingsChange{True{}, +next}}: addedAgain(PM.addSourceToSettings(next, source, False{}), expectChange, expected)
    case _: False{}

def filtered(+source: String) -> Settings.PackageSource:
  Settings.FilteredPackage{source, Settings.PackageFilter{None{}, Some{["extensions/main.ts"]}, Some{Nil{}}, Some{["prompts/review.md"]}, Some{["themes/dark.json"]}}, R.new(V.Value)}

def encodedList(packages: List<&2, Settings.PackageSource>) -> List<&2, V.Value>:
  match packages:
    case Nil{}: Nil{}
    case pkg <> rest: Settings.encodePackageSource(pkg) <> encodedList(rest)

def encodedPackages(packages: List<&2, Settings.PackageSource>) -> V.Value: V.ArrayValue{encodedList(packages)}

def filtersKept(result: Result<&2, &2, String, PM.SettingsChange>) -> Bool:
  match result:
    case Done{PM.SettingsChange{True{}, next}}: V.equal(encodedPackages(globalPackages(next)), encodedPackages([filtered("git:github.com/user/repo@v2")]))
    case _: False{}

def storedThenAdded(+c: PM.Context, stored: Result<&2, &2, Settings.Error, Settings.SettingsManager>) -> Bool:
  match c stored:
    case PM.Context{environment, _, cwd, agentDir, home} Done{settings}: filtersKept(PM.addSourceToSettings(PM.Context{environment, settings, cwd, agentDir, home}, "git:github.com/user/repo@v2", False{}))
    case _ _: False{}

def preservesFilters(+c: PM.Context) -> Bool:
  match c:
    case PM.Context{environment, settings, cwd, agentDir, home}: storedThenAdded(PM.Context{environment, settings, cwd, agentDir, home}, Settings.setPackages([filtered("git:github.com/user/repo@v1")], settings))

def settingsNormalization(+tempDir: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    a : PM.Context <- fresh(tempDir, home)
    storesGlobal(a, tempDir)
    b : PM.Context <- fresh(tempDir, home)
    storesProject(b, tempDir)
    c : PM.Context <- fresh(tempDir, home)
    removesEquivalent(c, tempDir)
    d : PM.Context <- fresh(tempDir, home)
    check(secondAdd(PM.addSourceToSettings(d, "git:github.com/user/repo@v1", False{}), "git:github.com/user/repo@v1", False{}, "git:github.com/user/repo@v1"), "DefaultPackageManager settings source normalization should return false when adding the same git source with the same ref")
    e : PM.Context <- fresh(tempDir, home)
    check(secondAdd(PM.addSourceToSettings(e, "git:github.com/user/repo@v1", False{}), "git:github.com/user/repo@v2", True{}, "git:github.com/user/repo@v2"), "DefaultPackageManager settings source normalization should update the ref when adding the same git source with a different ref")
    f : PM.Context <- fresh(tempDir, home)
    check(preservesFilters(f), "DefaultPackageManager settings source normalization should preserve package filters when replacing a package source ref")

def sameIdentity(+c: PM.Context, sources: List<&2, String>, +expected: String) -> Bool:
  match sources:
    case Nil{}: True{}
    case source <> rest: identityIs(identity(c, source), expected) && sameIdentity(c, rest, expected)

def httpsPrefix() -> String: "DefaultPackageManager HTTPS git URL parsing (old behavior) "

def httpsParsing(+c: PM.Context) -> IO(Unit):
  +prefix = httpsPrefix()
  do IO<Unit>:
    check(gitIs(PM.parseSource(c, "https://github.com/user/repo"), "github.com", "user/repo", None{}, None{}, Some{False{}}), prefix ++ "should parse HTTPS GitHub URLs correctly")
    check(gitIs(PM.parseSource(c, "git:https://github.com/user/repo"), "github.com", "user/repo", None{}, None{}, None{}), prefix ++ "should parse HTTPS URLs with git: prefix")
    check(gitIs(PM.parseSource(c, "https://github.com/user/repo@v1.2.3"), "github.com", "user/repo", None{}, Some{Some{"v1.2.3"}}, Some{True{}}), prefix ++ "should parse HTTPS URLs with ref")
    check(gitIs(PM.parseSource(c, "git:github.com/user/repo"), "github.com", "user/repo", None{}, None{}, None{}), prefix ++ "should parse host/path shorthand only with git: prefix")
    check(isLocal(PM.parseSource(c, "github.com/user/repo"), None{}), prefix ++ "should treat host/path shorthand as local without git: prefix")
    check(gitIs(PM.parseSource(c, "https://github.com/user/repo.git"), "github.com", "user/repo", None{}, None{}, None{}), prefix ++ "should parse HTTPS URLs with .git suffix")
    check(gitIs(PM.parseSource(c, "https://gitlab.com/user/repo"), "gitlab.com", "user/repo", None{}, None{}, None{}), prefix ++ "should parse GitLab HTTPS URLs")
    check(gitIs(PM.parseSource(c, "https://bitbucket.org/user/repo"), "bitbucket.org", "user/repo", None{}, None{}, None{}), prefix ++ "should parse Bitbucket HTTPS URLs")
    check(gitIs(PM.parseSource(c, "https://codeberg.org/user/repo"), "codeberg.org", "user/repo", None{}, None{}, None{}), prefix ++ "should parse Codeberg HTTPS URLs")
    check(sameIdentity(c, ["https://github.com/user/repo", "https://github.com/user/repo@v1.0.0", "git:github.com/user/repo", "https://github.com/user/repo.git"], "git:github.com/user/repo"), prefix ++ "should generate correct package identity for protocol and git:-prefixed URLs")
    check(sameIdentity(c, ["https://github.com/user/repo", "git:github.com/user/repo", "https://github.com/user/repo.git"], "git:github.com/user/repo"), prefix ++ "should deduplicate git URLs with different supported formats")
    check(gitIs(PM.parseSource(c, "https://github.com/user/repo@main"), "github.com", "user/repo", None{}, Some{Some{"main"}}, Some{True{}}) && gitIs(PM.parseSource(c, "https://github.com/user/repo@feature/branch"), "github.com", "user/repo", None{}, Some{Some{"feature/branch"}}, None{}), prefix ++ "should handle HTTPS URLs with refs in resolve")

def run(+tempDir: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    +c : PM.Context <- fresh(tempDir, home)
    sshCases(c)
    sourceParsing(c)
    gitInstallPaths(c)
    httpsParsing(c)
    settingsNormalization(tempDir, home)

def modeOf(result: Result<&1, &1, U32 & String, U32>) -> Maybe<&2, U32>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def assertions(+tempDir: String, +home: String, modeText: String) -> IO(Unit):
  do IO<Unit>:
    c : PM.Context <- fresh(tempDir, home)
    temporaryInstall(c, Path.join(tempDir, "agent"), U32.read(modeText))
    run(tempDir, home)

def created(+tempDir: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    c : PM.Context <- fresh(tempDir, home)
    path : Result<&2, &2, String, String> <- PM.getManagedNpmInstallPath(c, "left-pad", PM.TemporarySource{})
    IO.print("created")

def started(args: List<String>) -> IO(Unit):
  match args:
    case tempDir <> home <> modeText <> Nil{}: assertions(tempDir, home, modeText)
    case tempDir <> home <> Nil{}: created(tempDir, home)
    case _: IO.die(Unit, 2, "usage: package-sources <tempDir> <home> [temp-mode]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
