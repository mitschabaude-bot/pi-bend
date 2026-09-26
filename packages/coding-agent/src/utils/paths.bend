import Base
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/uri-component.bend as URI
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/unicode.bend as Unicode
import ../../../runtime/src/idna.bend as IDNA

# Pure path-input policy. The host supplies cwd/home and its reusable URL
# context; no environment lookup or filesystem access is hidden in normalization.
type Environment is Data:
  Environment{cwd: String, home: String, url: URL.Context}

type PathInputOptions is Data:
  PathInputOptions{trim: Bool, expandTilde: Bool, homeDir: Maybe<&2, String>, stripAtPrefix: Bool, normalizeUnicodeSpaces: Bool}

type Error is Data:
  InvalidWorkingDirectory{}
  InvalidURL{cause: URL.Error}
  NonLocalFileURL{}
  EncodedPathSeparator{}
  InvalidPercentEncoding{}

def defaults() -> PathInputOptions:
  PathInputOptions{False{}, True{}, None{}, False{}, False{}}

def toolOptions() -> PathInputOptions:
  PathInputOptions{False{}, True{}, None{}, True{}, True{}}

def unicodeSpace(+code: U32) -> Bool:
  U32.is_eq(code, 160) || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288)

def spaces(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code}, rest}: spaces(rest, SCon{Chr{Bool.pick(U32, unicodeSpace(code), 32, code)}, reversed})

def stripAt(text: String) -> String:
  match text:
    case SCon{'@', rest}: rest
    case other: other

def prepare(input: String, trimming: Bool, normalizeSpaces: Bool, strip: Bool) -> String:
  +trimmed = Bool.pick(String -> String, trimming, Text.trim, value => value)(input)
  +normalized = Bool.pick(Unit -> String, normalizeSpaces, _ => spaces(trimmed, ""), _ => trimmed)(Unit{})
  Bool.pick(String -> String, strip, stripAt, value => value)(normalized)

def encodedSeparator(text: String) -> Bool:
  match text:
    case SCon{'%', SCon{'2', SCon{'f', _}}}: True{}
    case SCon{'%', SCon{'2', SCon{'F', _}}}: True{}
    case SCon{_, rest}: encodedSeparator(rest)
    case SNil{}: False{}

def decoded(value: Maybe<&2, String>) -> Result<&2, &2, Error, String>:
  match value:
    case Some{path}: Done{path}
    case None{}: Fail{InvalidPercentEncoding{}}

def pathname(+path: String) -> Result<&2, &2, Error, String>:
  Bool.pick(Unit -> Result<&2, &2, Error, String>, encodedSeparator(path), _ => Fail{EncodedPathSeparator{}}, _ => decoded(URI.decode(path)))(Unit{})

def fileURL(result: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, Error, String>:
  match result:
    case Fail{cause}: Fail{InvalidURL{cause}}
    case Done{URL.URL{URL.File{}, _, _, Some{URL.Empty{}}, _, path, _, _}}: pathname(URL.serializePath(path))
    case _: Fail{NonLocalFileURL{}}

def maybeURL(context: URL.Context, +text: String) -> Result<&2, &2, Error, String>:
  Bool.pick(Unit -> Result<&2, &2, Error, String>, String.starts_with(text, "file://"), _ => fileURL(URL.parse(context, text)), _ => Done{text})(Unit{})

def expand(context: URL.Context, home: String, tilde: Bool, text: String) -> Result<&2, &2, Error, String>:
  match tilde text:
    case True{} "~": Done{home}
    case True{} SCon{'~', SCon{'/', rest}}: Done{Path.join(home, rest)}
    case _ other: maybeURL(context, other)

def normalizePath(environment: Environment, input: String, options: PathInputOptions) -> Result<&2, &2, Error, String>:
  match environment options:
    case Environment{_, home, context} PathInputOptions{trimming, tilde, override, strip, normalizeSpaces}:
      expand(context, Maybe.default(&2, String, override, home), tilde, prepare(input, trimming, normalizeSpaces, strip))

def absolute(value: Maybe<&2, String>) -> Result<&2, &2, Error, String>:
  match value:
    case Some{path}: Done{path}
    case None{}: Fail{InvalidWorkingDirectory{}}

def resolved(cwd: String, input: Result<&2, &2, Error, String>, base: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, String>:
  match input base:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{path} Done{directory}:
      Result.bind(&2, &2, Error, String, String, absolute(Path.resolve(cwd, directory)), root => absolute(Path.resolve(root, path)))

def resolvePath(+environment: Environment, input: String, base: String, options: PathInputOptions) -> Result<&2, &2, Error, String>:
  match environment:
    case Environment{cwd, _, _}:
      resolved(cwd, normalizePath(environment, input, options), normalizePath(environment, base, defaults()))

def resolveToCwd(environment: Environment, input: String, cwd: String) -> Result<&2, &2, Error, String>:
  resolvePath(environment, input, cwd, toolOptions())


# Explicit IO entry point for callers that want the process defaults.
def loadHome(context: URL.Context, cwd: Result<&2, &2, FS.Error, String>) -> IO(Result<&2, &2, FS.Error, Environment>):
  match cwd:
    case Fail{cause}: IO.pure(Result<&2, &2, FS.Error, Environment>, Fail{cause})
    case Done{directory}:
      do IO<Result<&2, &2, FS.Error, Environment>>:
        home : Result<&2, &2, FS.Error, String> <- FS.homedir()
        return Result.map(&2, &2, FS.Error, String, Environment, value => Environment{directory, value, context}, home)

def loadEnvironment(context: URL.Context) -> IO(Result<&2, &2, FS.Error, Environment>):
  do IO<Result<&2, &2, FS.Error, Environment>>:
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    loadHome(context, cwd)

# Pi probes real filenames before trying its macOS screenshot spelling variants.
def screenshot(path: String, reversed: String) -> String:
  match path:
    case SCon{' ',SCon{+a,SCon{+m,SCon{'.',rest}}}}:
      +amPm = (Char.is_eq(a,'A') || Char.is_eq(a,'a') || Char.is_eq(a,'P') || Char.is_eq(a,'p')) && (Char.is_eq(m,'M') || Char.is_eq(m,'m'))
      screenshot(rest,SCon{'.',SCon{m,SCon{a,SCon{Bool.pick(Char,amPm,'\u{202f}',' '),reversed}}}})
    case SCon{char,rest}: screenshot(rest,SCon{char,reversed})
    case SNil{}: String.reverse(reversed)

def curly(path: String, reversed: String) -> String:
  match path:
    case SCon{+char,rest}: curly(rest,SCon{Bool.pick(Char,Char.is_eq(char,'\''),'\u{2019}',char),reversed})
    case SNil{}: String.reverse(reversed)

def normalization(environment: Environment) -> Unicode.Tables:
  match environment:
    case Environment{_,_,URL.Context{IDNA.Context{_,tables,_},_}}: tables

def findPath(candidates: List<&2,String>, +original: String, found: Maybe<&2,String>) -> IO(String):
  match candidates found:
    case _ Some{path}: IO.pure(String,path)
    case Nil{} None{}: IO.pure(String,original)
    case +path <> rest None{}:
      do IO<String>:
        found : Bool <- FS.accessible(path,0)
        findPath(rest,original,Bool.pick(Maybe<&2,String>,found,Some{path},None{}))

def resolvedReadPath(environment: Environment, +original: String) -> IO(String):
  +nfd = Unicode.nfd(normalization(environment),original)
  findPath(original <> screenshot(original,"") <> nfd <> curly(original,"") <> curly(nfd,"") <> Nil{},original,None{})

# upstream getFileRevision: a stamp that changes when the file does. The
# filesystem primitives expose the size and the modification time (seconds
# and nanoseconds), not upstream's device, inode and change time, so a
# same-size rewrite within one mtime tick is not observed.
def revisionOf(size: Result<&1,&1,U32 & String,U32 & U32>,modified: Result<&1,&1,U32 & String,U32 & U32 & U32>) -> Maybe<&2,String>:
  match size modified:
    case Done{(high,low)} Done{(secondsHigh,(secondsLow,nanos))}: Some{U32.show(high) ++ ":" ++ U32.show(low) ++ ":" ++ U32.show(secondsHigh) ++ ":" ++ U32.show(secondsLow) ++ ":" ++ U32.show(nanos)}
    case _ _: None{}
def getFileRevision(+path: String) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    size : Result<&1,&1,U32 & String,U32 & U32> <- File.size_bytes(path)
    modified : Result<&1,&1,U32 & String,U32 & U32 & U32> <- File.modified_time(path)
    return revisionOf(size,modified)

# upstream canonicalizePath: the real path, following symlinks; the raw path
# when resolution fails (a missing target or a dangling link).
def canonicalized(+path: String, real: Result<&2,&2,FS.Error,String>) -> String:
  match real:
    case Done{found}: found
    case Fail{_}: path

def canonicalizePath(+path: String) -> IO(String):
  do IO<String>:
    real : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
    return canonicalized(path, real)

# upstream isLocalPath: not a package source (npm:, git:, github:) or a remote
# URL; bare names, relative paths and file: URLs are local.
def isLocalPath(value: String) -> Bool:
  +trimmed = Text.trim(value)
  Bool.not(String.starts_with(trimmed, "npm:") || String.starts_with(trimmed, "git:") || String.starts_with(trimmed, "github:") || String.starts_with(trimmed, "http:") || String.starts_with(trimmed, "https:") || String.starts_with(trimmed, "ssh:"))

# upstream normalizeWindowsShellPath: Git Bash, MSYS, Cygwin and WSL drive
# paths (/c/x, /cygdrive/c/x, /mnt/c/x) to C:\x; other forms unchanged. It is
# a pure conversion; upstream applies it in normalizePath only on Windows, so
# the POSIX path pipeline above never calls it.
def asciiLetter(+code: U32) -> Bool:
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122))

def lineTerminator(+code: U32) -> Bool:
  U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

def singleLine(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: Bool.not(lineTerminator(code)) && singleLine(rest)

def backslashes(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'/', rest}: backslashes(rest, SCon{'\\', reversed})
    case SCon{char, rest}: backslashes(rest, SCon{char, reversed})

def upperLetter(+code: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_ge(code, 97), (code - 32 : U32), code)}

def driveOf(+code: U32, suffix: String) -> String:
  SCon{upperLetter(code), SCon{':', SCon{'\\', backslashes(suffix, "")}}}

# The drive letter and optional "/rest" after an optional mount prefix.
def drivePath(text: String) -> Maybe<&2, String>:
  match text:
    case SCon{Chr{+code}, SNil{}}: Bool.pick(Maybe<&2, String>, asciiLetter(code), Some{driveOf(code, "")}, None{})
    case SCon{Chr{+code}, SCon{'/', +rest}}: Bool.pick(Maybe<&2, String>, asciiLetter(code) && singleLine(rest), Some{driveOf(code, rest)}, None{})
    case _: None{}

def withoutMount(text: String) -> Maybe<&2, String>:
  match text:
    case SCon{'m', SCon{'n', SCon{'t', SCon{'/', rest}}}}: Some{rest}
    case SCon{'c', SCon{'y', SCon{'g', SCon{'d', SCon{'r', SCon{'i', SCon{'v', SCon{'e', SCon{'/', rest}}}}}}}}}: Some{rest}
    case _: None{}

# The regex backtracks: a mount prefix that leaves no drive path retries the
# whole text as one.
def mountFirst(+text: String) -> Maybe<&2, String>:
  Maybe.or(&2, String, Maybe.bind(&2, String, String, withoutMount(text), drivePath), drivePath(text))

def windowsPath(+filePath: String, converted: Maybe<&2, String>) -> String:
  match converted:
    case Some{path}: path
    case None{}: filePath

def unixDrivePath(+rest: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.contains(rest, "\\"), None{}, mountFirst(rest))

def shellDrivePath(text: String) -> Maybe<&2, String>:
  match text:
    case SCon{'/', SCon{'/', _}}: None{}
    case SCon{'/', rest}: unixDrivePath(rest)
    case _: None{}

def normalizeWindowsShellPath(+filePath: String) -> String:
  windowsPath(filePath, shellDrivePath(filePath))

# upstream getCwdRelativePath: the path relative to cwd when it lies inside
# (itself is "."), otherwise None. Both are resolved first, cwd against the
# process working directory.
def insideCwd(+relative: String) -> Maybe<&2, String>:
  +inside = String.eq(relative, "") || (Bool.not(String.eq(relative, "..")) && Bool.not(String.starts_with(relative, "../")) && Bool.not(Path.isAbsolute(relative)))
  Bool.pick(Maybe<&2, String>, inside, Some{Bool.pick(String, String.eq(relative, ""), ".", relative)}, None{})

def relativeInside(+resolvedCwd: String, path: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, Maybe<&2, String>>:
  Result.map(&2, &2, Error, String, Maybe<&2, String>, resolvedPath => insideCwd(Path.relative(resolvedCwd, resolvedPath)), path)

def relativeFrom(+environment: Environment, filePath: String, cwd: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match cwd:
    case Fail{error}: Fail{error}
    case Done{+resolvedCwd}: relativeInside(resolvedCwd, resolvePath(environment, filePath, resolvedCwd, defaults()))

def getCwdRelativePath(+environment: Environment, filePath: String, cwd: String) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match environment:
    case Environment{processCwd, _, _}:
      relativeFrom(environment, filePath, resolvePath(environment, cwd, processCwd, defaults()))

# upstream formatPathRelativeToCwdOrAbsolute: the cwd-relative path when it is
# inside cwd, otherwise the absolute path (POSIX separators already).
def relativeOrAbsolute(+environment: Environment, +cwd: String, absolute: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, String>:
  match absolute:
    case Fail{error}: Fail{error}
    case Done{+absolutePath}: Result.map(&2, &2, Error, Maybe<&2, String>, String, relative => Maybe.default(&2, String, relative, absolutePath), getCwdRelativePath(environment, absolutePath, cwd))

def formatPathRelativeToCwdOrAbsolute(+environment: Environment, filePath: String, +cwd: String) -> Result<&2, &2, Error, String>:
  relativeOrAbsolute(environment, cwd, resolvePath(environment, filePath, cwd, defaults()))

# upstream core/tools/path-utils expandPath: normalizePath with Unicode space
# normalization and a stripped @ prefix (tool path input).
def expandPath(environment: Environment, filePath: String) -> Result<&2, &2, Error, String>:
  normalizePath(environment, filePath, toolOptions())

# upstream core/tools/path-utils resolveReadPath: resolveToCwd, then the first
# existing macOS spelling variant (resolvedReadPath above).
def readPathOf(+environment: Environment, resolved: Result<&2, &2, Error, String>) -> IO(Result<&2, &2, Error, String>):
  match resolved:
    case Fail{error}: IO.pure(Result<&2, &2, Error, String>, Fail{error})
    case Done{path}:
      do IO<Result<&2, &2, Error, String>>:
        found : String <- resolvedReadPath(environment, path)
        return Done{found}

def resolveReadPath(+environment: Environment, filePath: String, cwd: String) -> IO(Result<&2, &2, Error, String>):
  readPathOf(environment, resolveToCwd(environment, filePath, cwd))
