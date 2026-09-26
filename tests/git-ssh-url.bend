import Base
import ../packages/coding-agent/src/utils/git.bend as Git
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/test/utf8-runner.bend as Wire

# upstream packages/coding-agent/test/git-ssh-url.test.ts (all cases, run
# without arguments) and a differential mode: each argument is one source as
# comma-separated code points; each output line is parseGitUrl's result, which
# tests/git_url_check.py compares with the pinned upstream function.

def context() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def sameRef(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

# toMatchObject on host, path, repo and (when given) ref.
def matches(result: Maybe<&2, Git.GitSource>, +host: String, +path: String, +repo: String, ref: Maybe<&2, String>) -> Bool:
  match result:
    case Some{Git.GitSource{r, h, p, found, _}}: String.eq(h, host) && String.eq(p, path) && String.eq(r, repo) && Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, wanted => sameRef(found, Some{wanted}), ref), True{})
    case None{}: False{}

def isNull(result: Maybe<&2, Git.GitSource>) -> Bool: Maybe.is_none(&2, Git.GitSource, result)

def allNull(+context: URL.Context, sources: List<&2, String>) -> Bool:
  match sources:
    case Nil{}: True{}
    case source <> rest: isNull(Git.parseGitUrl(context, source)) && allNull(context, rest)

def named(+c: URL.Context) -> IO(Unit):
  do IO<Unit>:
    check(matches(Git.parseGitUrl(c, "https://github.com/user/repo"), "github.com", "user/repo", "https://github.com/user/repo", None{}), "Git URL Parsing protocol URLs (accepted without git: prefix) should parse HTTPS URL")
    check(matches(Git.parseGitUrl(c, "ssh://git@github.com/user/repo"), "github.com", "user/repo", "ssh://git@github.com/user/repo", None{}), "Git URL Parsing protocol URLs (accepted without git: prefix) should parse ssh:// URL")
    check(matches(Git.parseGitUrl(c, "https://github.com/user/repo@v1.0.0"), "github.com", "user/repo", "https://github.com/user/repo", Some{"v1.0.0"}), "Git URL Parsing protocol URLs (accepted without git: prefix) should parse protocol URL with ref")
    check(matches(Git.parseGitUrl(c, "git:git@github.com:user/repo"), "github.com", "user/repo", "git@github.com:user/repo", None{}), "Git URL Parsing shorthand URLs (accepted only with git: prefix) should parse git@host:path with git: prefix")
    check(matches(Git.parseGitUrl(c, "git:github.com/user/repo"), "github.com", "user/repo", "https://github.com/user/repo", None{}), "Git URL Parsing shorthand URLs (accepted only with git: prefix) should parse host/path shorthand with git: prefix")
    check(matches(Git.parseGitUrl(c, "git:git@github.com:user/repo@v1.0.0"), "github.com", "user/repo", "git@github.com:user/repo", Some{"v1.0.0"}), "Git URL Parsing shorthand URLs (accepted only with git: prefix) should parse shorthand with ref and git: prefix")
    check(allNull(c, "git:git@evil.example:../../victim/repo" <> "https://evil.example/..%2F..%2Fvictim/repo" <> "https://evil.example/..%2F..%2Fvictim/repo%" <> "git:git@evil.example:/absolute/repo" <> "git:git@evil.example:user\\repo/name" <> "git:git@evil.example:user/repo\u{0}name" <> Nil{}), "Git URL Parsing should reject unsafe git install path inputs")
    check(isNull(Git.parseGitUrl(c, "git@github.com:user/repo")), "Git URL Parsing unsupported without git: prefix should reject git@host:path without git: prefix")
    check(isNull(Git.parseGitUrl(c, "github.com/user/repo")), "Git URL Parsing unsupported without git: prefix should reject host/path shorthand without git: prefix")
    check(isNull(Git.parseGitUrl(c, "user/repo")), "Git URL Parsing unsupported without git: prefix should reject user/repo shorthand")

def shown(result: Maybe<&2, Git.GitSource>) -> String:
  match result:
    case None{}: "null"
    case Some{Git.GitSource{repo, host, path, ref, pinned}}: Wire.showText(repo) ++ "|" ++ Wire.showText(host) ++ "|" ++ Wire.showText(path) ++ "|" ++ Maybe.default(&2, String, Maybe.map(&2, String, String, Wire.showText, ref), "-") ++ "|" ++ Bool.pick(String, pinned, "true", "false")

def differential(args: List<String>, +c: URL.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case input <> rest:
      do IO<Unit>:
        IO.print(shown(Git.parseGitUrl(c, Wire.fromScalars(Wire.parseNumbers(input)))))
        differential(rest, c)

def started(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: named(context())
    case _ <> rest: differential(rest, context())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
