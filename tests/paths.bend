import Base
import ../packages/coding-agent/src/utils/paths.bend as P
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/string.bend as Strings

# upstream packages/coding-agent/test/paths.test.ts and path-utils.test.ts.
# tests/paths_check.py creates each case's files and symlinks under a fixture
# root (one directory per upstream temporary directory) and passes that root,
# its real path and a home directory. The environment's home stands in for
# os.homedir() and TMP for os.tmpdir().

def TMP() -> String: "/tmp"

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def context() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def yields(result: Result<&2, &2, P.Error, String>, +expected: String) -> Bool:
  match result:
    case Done{value}: String.eq(value, expected)
    case Fail{_}: False{}

def failed(result: Result<&2, &2, P.Error, String>) -> Bool:
  match result:
    case Done{_}: False{}
    case Fail{_}: True{}

def relativeIs(result: Result<&2, &2, P.Error, Maybe<&2, String>>, expected: Maybe<&2, String>) -> Bool:
  match result expected:
    case Done{Some{value}} Some{wanted}: String.eq(value, wanted)
    case Done{None{}} None{}: True{}
    case _ _: False{}

def lacks(result: Result<&2, &2, P.Error, String>, +text: String) -> Bool:
  match result:
    case Done{value}: Bool.not(String.contains(value, text))
    case Fail{_}: False{}

# Node's pathToFileURL for the fixture's plain ASCII paths: spaces escaped.
def fileURL(path: String) -> String: "file://" ++ Strings.replaceAll(path, " ", "%20")

def join(left: String, right: String) -> String: Path.join(left, right)

def canonicalizeCases(+root: String, +real: String) -> IO(Unit):
  do IO<Unit>:
    file : String <- P.canonicalizePath(join(root, "regular/file.txt"))
    check(String.eq(file, join(real, "regular/file.txt")), "canonicalizePath returns the real path for a regular file")
    link : String <- P.canonicalizePath(join(root, "symlink/link.txt"))
    check(String.eq(link, join(real, "symlink/target.txt")), "canonicalizePath resolves symlinks to their targets")
    directory : String <- P.canonicalizePath(join(root, "directory/link-dir"))
    check(String.eq(directory, join(real, "directory/target-dir")), "canonicalizePath resolves directory symlinks")
    missing : String <- P.canonicalizePath(join(root, "missing/no-such-file"))
    check(String.eq(missing, join(root, "missing/no-such-file")), "canonicalizePath falls back to the raw path when the target does not exist")
    dangling : String <- P.canonicalizePath(join(root, "dangling/link.txt"))
    check(String.eq(dangling, join(root, "dangling/link.txt")), "canonicalizePath falls back to the raw path for a dangling symlink")

def cwdRelativeCases(+environment: P.Environment) -> IO(Unit):
  +cwd = join(TMP(), "pi-paths-cwd")
  do IO<Unit>:
    check(relativeIs(P.getCwdRelativePath(environment, join(cwd, "..config/AGENTS.md"), cwd), Some{"..config/AGENTS.md"}), "getCwdRelativePath keeps cwd-relative names that start with dots")
    check(relativeIs(P.getCwdRelativePath(environment, join(cwd, "../AGENTS.md"), cwd), None{}), "getCwdRelativePath rejects parent-directory traversals")

def percentPaths(+environment: P.Environment, paths: List<&2, String>, +base: String) -> Bool:
  match paths:
    case Nil{}: True{}
    case +path <> rest: yields(P.resolvePath(environment, path, base, P.defaults()), path) && percentPaths(environment, rest, base)

def resolvePathCases(+environment: P.Environment, +home: String, +root: String) -> IO(Unit):
  +cwd = join(TMP(), "pi-paths-cwd")
  +spaced = join(root, "urls/file with spaces.txt")
  +percent = join(root, "percent")
  do IO<Unit>:
    check(yields(P.normalizePath(environment, "~", P.defaults()), home) && yields(P.normalizePath(environment, "~/file.txt", P.defaults()), join(home, "file.txt")) && yields(P.resolvePath(environment, "~draft.md", cwd, P.defaults()), join(cwd, "~draft.md")) && yields(P.normalizePath(environment, "~draft.md", P.defaults()), "~draft.md"), "resolvePath expands only home tilde shortcuts")
    check(yields(P.resolvePath(environment, "subdir/file.txt", cwd, P.defaults()), join(cwd, "subdir/file.txt")) && yields(P.resolvePath(environment, "subdir/file.txt", fileURL(cwd), P.defaults()), join(cwd, "subdir/file.txt")), "resolvePath resolves relative paths against the base directory")
    check(yields(P.resolvePath(environment, fileURL(spaced), join(root, "urls/base"), P.defaults()), spaced), "resolvePath accepts file URLs")
    check(failed(P.resolvePath(environment, "file:///%E0%A4%A", cwd, P.defaults())), "resolvePath throws for invalid file URLs")
    check(percentPaths(environment, join(percent, "report%2026.md") <> join(percent, "foo%2Fbar") <> join(percent, "malformed%A.md") <> Nil{}, join(percent, "base")), "resolvePath preserves POSIX absolute paths with literal percent sequences")

def unchanged(paths: List<&2, String>) -> Bool:
  match paths:
    case Nil{}: True{}
    case +path <> rest: String.eq(P.normalizeWindowsShellPath(path), path) && unchanged(rest)

def windowsCases() -> IO(Unit):
  do IO<Unit>:
    check(String.eq(P.normalizeWindowsShellPath("/c/Users/example/project"), "C:\\Users\\example\\project") && String.eq(P.normalizeWindowsShellPath("/cygdrive/d/work"), "D:\\work") && String.eq(P.normalizeWindowsShellPath("/mnt/e/source"), "E:\\source") && String.eq(P.normalizeWindowsShellPath("/c"), "C:\\"), "normalizeWindowsShellPath converts Git Bash, MSYS, Cygwin, and WSL drive paths")
    check(unchanged("C:/Users/example" <> "C:\\Users\\example" <> "//server/share/file" <> "/c/Users\\example" <> "relative/file" <> "/tmp/file" <> Nil{}), "normalizeWindowsShellPath leaves other path forms unchanged")

def localCases() -> IO(Unit):
  do IO<Unit>:
    check(P.isLocalPath("my-package"), "isLocalPath returns true for bare names")
    check(P.isLocalPath("./foo"), "isLocalPath returns true for relative paths")
    check(P.isLocalPath("file:///tmp/foo"), "isLocalPath returns true for file URLs")
    check(Bool.not(P.isLocalPath("npm:package")), "isLocalPath returns false for npm: protocol")
    check(Bool.not(P.isLocalPath("git://repo")), "isLocalPath returns false for git: protocol")
    check(Bool.not(P.isLocalPath("https://example.com")), "isLocalPath returns false for https: protocol")

def expandCases(+environment: P.Environment) -> IO(Unit):
  +cwd = join(TMP(), "pi-path-utils-cwd")
  +absolute = join(TMP(), "absolute/path/file.txt")
  do IO<Unit>:
    check(lacks(P.expandPath(environment, "~"), "~"), "path-utils expandPath should expand ~ to home directory")
    check(lacks(P.expandPath(environment, "~/Documents/file.txt"), "~/"), "path-utils expandPath should expand ~/path to home directory")
    check(yields(P.expandPath(environment, "~draft.md"), "~draft.md") && yields(P.expandPath(environment, "@~draft.md"), "~draft.md"), "path-utils expandPath should keep tilde-prefixed filenames literal")
    check(yields(P.expandPath(environment, "file\u{a0}name.txt"), "file name.txt"), "path-utils expandPath should normalize Unicode spaces")
    check(yields(P.resolveToCwd(environment, absolute, join(TMP(), "some/cwd")), absolute), "path-utils resolveToCwd should resolve absolute paths as-is")
    check(yields(P.resolveToCwd(environment, "relative/file.txt", "/some/cwd"), "/some/cwd/relative/file.txt"), "path-utils resolveToCwd should resolve relative paths against cwd")
    check(yields(P.resolveToCwd(environment, "~draft.md", cwd), join(cwd, "~draft.md")) && yields(P.resolveToCwd(environment, "@~draft.md", cwd), join(cwd, "~draft.md")), "path-utils resolveToCwd should resolve tilde-prefixed filenames against cwd")

def readPath(+environment: P.Environment, +dir: String, name: String) -> IO(Result<&2, &2, P.Error, String>):
  P.resolveReadPath(environment, name, dir)

def accented(result: Result<&2, &2, P.Error, String>, +dir: String) -> Bool:
  match result:
    case Done{+value}: String.starts_with(value, dir) && String.starts_with(value, join(dir, "file")) && String.ends_with(value, ".txt") && Nat.is_gt(String.length(value), String.length(join(dir, "file.txt"))) && String.eq(value, join(dir, "file\u{65}\u{301}.txt"))
    case Fail{_}: False{}

def readPathCases(+environment: P.Environment, +root: String) -> IO(Unit):
  +existing = join(root, "read-existing")
  +nfd = join(root, "read-nfd")
  +curly = join(root, "read-curly")
  +combined = join(root, "read-combined")
  +upper = join(root, "read-ampm")
  +lower = join(root, "read-ampm-lower")
  do IO<Unit>:
    found : Result<&2, &2, P.Error, String> <- readPath(environment, existing, "test-file.txt")
    check(yields(found, join(existing, "test-file.txt")), "path-utils resolveReadPath should resolve existing file path")
    decomposed : Result<&2, &2, P.Error, String> <- readPath(environment, nfd, "file\u{e9}.txt")
    check(accented(decomposed, nfd), "path-utils resolveReadPath should handle NFC vs NFD Unicode normalization (macOS filenames with accents)")
    quoted : Result<&2, &2, P.Error, String> <- readPath(environment, curly, "Capture d'cran.txt")
    check(yields(quoted, join(curly, "Capture d\u{2019}cran.txt")), "path-utils resolveReadPath should handle curly quotes vs straight quotes (macOS filenames)")
    both : Result<&2, &2, P.Error, String> <- readPath(environment, combined, "Capture d'\u{e9}cran.txt")
    check(yields(both, join(combined, "Capture d\u{2019}\u{e9}cran.txt")), "path-utils resolveReadPath should handle combined NFC + curly quote (French macOS screenshots)")
    shot : Result<&2, &2, P.Error, String> <- readPath(environment, upper, "Screenshot 2024-01-01 at 10.00.00 AM.png")
    check(yields(shot, join(upper, "Screenshot 2024-01-01 at 10.00.00\u{202f}AM.png")), "path-utils resolveReadPath should handle macOS screenshot AM/PM variant with narrow no-break space")
    small : Result<&2, &2, P.Error, String> <- readPath(environment, lower, "Screenshot 2024-01-01 at 10.00.00 am.png")
    check(yields(small, join(lower, "Screenshot 2024-01-01 at 10.00.00\u{202f}am.png")), "path-utils resolveReadPath should handle macOS screenshot lowercase am/pm variant (en_AU locale)")

def environmentOf(home: String) -> P.Environment: P.Environment{"/", home, context()}

def run(+root: String, +real: String, +home: String) -> IO(Unit):
  +environment = environmentOf(home)
  do IO<Unit>:
    canonicalizeCases(root, real)
    cwdRelativeCases(environment)
    resolvePathCases(environment, home, root)
    windowsCases()
    localCases()
    expandCases(environment)
    readPathCases(environment, root)

def started(args: List<String>) -> IO(Unit):
  match args:
    case root <> real <> home <> Nil{}: run(root, real, home)
    case _: IO.die(Unit, 2, "usage: paths ROOT REAL-ROOT HOME")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
