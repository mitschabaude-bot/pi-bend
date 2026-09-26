import Base
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/uri-component.bend as URI
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/hosted-git-info.bend as Hosted

# upstream utils/git.ts: parse a git package source into its clone URL, host,
# repository path and optional ref. Hosted forms go through hosted-git-info
# (packages/runtime/src/hosted-git-info.bend); unknown hosts use the generic
# scp/URL/host-path forms. Shorthands need the git: prefix.

# upstream GitSource (its `type` is always "git"). `ref` is absent or
# non-empty; `pinned` says a ref was given, so the package is not updated.
type GitSource is Data:
  GitSource{repo: String, host: String, path: String, ref: Maybe<&2, String>, pinned: Bool}

# Text around the first occurrence of a character.
type Halves is Data:
  Halves{before: String, after: String}

type Split is Data:
  Split{repo: String, ref: Maybe<&2, String>}

# Text helpers
# ------------

def cut(text: String, +char: Char, +reversed: String) -> Maybe<&2, Halves>:
  match text:
    case SNil{}: None{}
    case SCon{+head, +rest}: Bool.pick(Unit -> Maybe<&2, Halves>, Char.is_eq(head, char), _ => Some{Halves{String.reverse(reversed), rest}}, _ => cut(rest, char, SCon{head, reversed}))(Unit{})

# The text before and after the first `char`.
def splitFirst(text: String, +char: Char) -> Maybe<&2, Halves>: cut(text, char, "")

def lineTerminator(+code: U32) -> Bool:
  U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

def dotRest(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: Bool.not(lineTerminator(code)) && dotRest(rest)

# JavaScript's `.+$`: at least one character and no line terminator.
def dotAll(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{+code}, rest}: Bool.not(lineTerminator(code)) && dotRest(rest)

def scpParts(pair: Maybe<&2, Halves>) -> Maybe<&2, Halves>:
  match pair:
    case Some{Halves{SCon{h, hs}, +path}}: Bool.pick(Maybe<&2, Halves>, dotAll(path), Some{Halves{SCon{h, hs}, path}}, None{})
    case _: None{}

# /^git@([^:]+):(.+)$/
def scpLike(text: String) -> Maybe<&2, Halves>:
  match text:
    case SCon{'g', SCon{'i', SCon{'t', SCon{'@', rest}}}}: scpParts(splitFirst(rest, ':'))
    case _: None{}

def stripLeadingSlashes(text: String) -> String:
  match text:
    case SCon{'/', rest}: stripLeadingSlashes(rest)
    case other: other

def withoutTrailingSlash(+text: String) -> String:
  Bool.pick(String, String.ends_with(text, "/"), String.take(text, Nat.sub(String.length(text), 1n)), text)

def withoutGitSuffix(+text: String) -> String:
  Bool.pick(String, String.ends_with(text, ".git"), String.take(text, Nat.sub(String.length(text), 4n)), text)

def okURL(result: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, URL.URL>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

# splitRef
# --------

def scpRepo(+host: String, path: String) -> String: "git@" ++ host ++ ":" ++ path

# A `path@ref` tail splits when both halves are non-empty.
def scpRef(+url: String, +host: String, pair: Maybe<&2, Halves>) -> Split:
  match pair:
    case Some{Halves{SCon{p, ps}, SCon{r, rs}}}: Split{scpRepo(host, SCon{p, ps}), Some{SCon{r, rs}}}
    case _: Split{url, None{}}

def scpSplit(+url: String, +host: String, path: String) -> Split: scpRef(url, host, splitFirst(path, '@'))

def urlRefSplit(+url: String, +parsed: URL.URL, pair: Maybe<&2, Halves>) -> Split:
  match pair:
    case Some{Halves{SCon{p, ps}, SCon{r, rs}}}: Split{withoutTrailingSlash(URL.href(URL.setPathname(parsed, "/" ++ SCon{p, ps}))), Some{SCon{r, rs}}}
    case _: Split{url, None{}}

def protocolSplit(+url: String, parsed: Maybe<&2, URL.URL>) -> Split:
  match parsed:
    case None{}: Split{url, None{}}
    case Some{+value}: urlRefSplit(url, value, splitFirst(stripLeadingSlashes(URL.pathname(value)), '@'))

def hostRefSplit(+url: String, +host: String, pair: Maybe<&2, Halves>) -> Split:
  match pair:
    case Some{Halves{SCon{p, ps}, SCon{r, rs}}}: Split{host ++ "/" ++ SCon{p, ps}, Some{SCon{r, rs}}}
    case _: Split{url, None{}}

def hostPathSplit(+url: String, pair: Maybe<&2, Halves>) -> Split:
  match pair:
    case None{}: Split{url, None{}}
    case Some{Halves{+host, path}}: hostRefSplit(url, host, splitFirst(path, '@'))

def splitOther(+context: URL.Context, +url: String) -> Split:
  Bool.pick(Unit -> Split, String.contains(url, "://"), _ => protocolSplit(url, okURL(URL.parse(context, url))), _ => hostPathSplit(url, splitFirst(url, '/')))(Unit{})

def splitScp(+context: URL.Context, +url: String, scp: Maybe<&2, Halves>) -> Split:
  match scp:
    case Some{Halves{+host, path}}: scpSplit(url, host, path)
    case None{}: splitOther(context, url)

def splitRef(+context: URL.Context, +url: String) -> Split: splitScp(context, url, scpLike(url))

# Validation
# ----------

def unsafeCandidate(+candidate: String, +allowSlash: Bool) -> Bool:
  String.contains(candidate, "\u{0}") || String.contains(candidate, "\\") || String.starts_with(candidate, "/") || (Bool.not(allowSlash) && String.contains(candidate, "/")) || List.contains(~String, ~String.eq, String.split(candidate, '/'), "..")

def unsafeDecoded(+value: String, +allowSlash: Bool, decoded: Maybe<&2, String>) -> Bool:
  match decoded:
    case None{}: True{}
    case Some{text}: unsafeCandidate(value, allowSlash) || unsafeCandidate(text, allowSlash)

def hasUnsafeGitInstallPart(+value: String, +allowSlash: Bool) -> Bool: unsafeDecoded(value, allowSlash, URI.decode(value))

def enoughSegments(+path: String) -> Bool: Nat.is_ge(List.length(&2, String, String.split(path, '/')), 2n)

def validSource(repo: String, +host: String, +normalizedPath: String, +ref: Maybe<&2, String>) -> Maybe<&2, GitSource>:
  +valid = Bool.not(String.is_empty(host)) && Bool.not(String.is_empty(normalizedPath)) && enoughSegments(normalizedPath) && Bool.not(hasUnsafeGitInstallPart(host, False{})) && Bool.not(hasUnsafeGitInstallPart(normalizedPath, True{}))
  Bool.pick(Maybe<&2, GitSource>, valid, Some{GitSource{repo, host, normalizedPath, ref, Maybe.is_some(&2, String, ref)}}, None{})

def buildGitSource(repo: String, host: String, +path: String, ref: Maybe<&2, String>) -> Maybe<&2, GitSource>:
  Bool.pick(Unit -> Maybe<&2, GitSource>, String.starts_with(path, "/"), _ => None{}, _ => validSource(repo, host, stripLeadingSlashes(withoutGitSuffix(path)), ref))(Unit{})

# parseGenericGitUrl
# ------------------

def urlSource(repo: String, ref: Maybe<&2, String>, parsed: Maybe<&2, URL.URL>) -> Maybe<&2, GitSource>:
  match parsed:
    case None{}: None{}
    case Some{+value}: buildGitSource(repo, URL.hostname(value), stripLeadingSlashes(URL.pathname(value)), ref)

def shorthandSource(+repoWithoutRef: String, ref: Maybe<&2, String>, pair: Maybe<&2, Halves>) -> Maybe<&2, GitSource>:
  match pair:
    case None{}: None{}
    case Some{Halves{+host, path}}: Bool.pick(Unit -> Maybe<&2, GitSource>, String.contains(host, ".") || String.eq(host, "localhost"), _ => buildGitSource("https://" ++ repoWithoutRef, host, path, ref), _ => None{})(Unit{})

def explicitProtocol(+text: String) -> Bool:
  String.starts_with(text, "https://") || String.starts_with(text, "http://") || String.starts_with(text, "ssh://") || String.starts_with(text, "git://")

def genericFrom(+context: URL.Context, +repoWithoutRef: String, +ref: Maybe<&2, String>, scp: Maybe<&2, Halves>) -> Maybe<&2, GitSource>:
  match scp:
    case Some{Halves{host, path}}: buildGitSource(repoWithoutRef, host, path, ref)
    case None{}: Bool.pick(Unit -> Maybe<&2, GitSource>, explicitProtocol(repoWithoutRef), _ => urlSource(repoWithoutRef, ref, okURL(URL.parse(context, repoWithoutRef))), _ => shorthandSource(repoWithoutRef, ref, splitFirst(repoWithoutRef, '/')))(Unit{})

def genericSplit(+context: URL.Context, split: Split) -> Maybe<&2, GitSource>:
  match split:
    case Split{+repo, ref}: genericFrom(context, repo, ref, scpLike(repo))

def parseGenericGitUrl(+context: URL.Context, +url: String) -> Maybe<&2, GitSource>: genericSplit(context, splitRef(context, url))

# parseGitUrl
# -----------

# hosted-git-info's user in pi's `${info.user}/${info.project}`: a null user
# prints as "null", so a Gist path keeps pi's install directory.
def hostedPath(user: Maybe<&2, String>, project: String) -> String:
  Maybe.default(&2, String, user, "null") ++ "/" ++ project

def nonEmpty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def projectHasAt(+ref: Maybe<&2, String>, info: Hosted.GitHost) -> Bool:
  match info:
    case Hosted.GitHost{_, _, _, _, project, _, _}: Maybe.is_some(&2, String, ref) && String.contains(project, "@")

def hostedSource(repo: String, +ref: Maybe<&2, String>, info: Hosted.GitHost) -> Maybe<&2, GitSource>:
  match info:
    case Hosted.GitHost{_, domain, user, _, project, committish, _}: buildGitSource(repo, domain, hostedPath(user, project), Maybe.or(&2, String, nonEmpty(committish), ref))

def hostedInfos(+context: URL.Context, candidates: List<&2, String>) -> List<&2, Maybe<&2, Hosted.GitHost>>:
  match candidates:
    case Nil{}: Nil{}
    case candidate <> rest: Hosted.fromUrl(context, candidate) <> hostedInfos(context, rest)

# The first candidate hosted-git-info knows, skipping one whose project still
# contains an @ after a ref was split off.
def firstAccepted(infos: List<&2, Maybe<&2, Hosted.GitHost>>, +ref: Maybe<&2, String>) -> Maybe<&2, Hosted.GitHost>:
  match infos:
    case Nil{}: None{}
    case None{} <> rest: firstAccepted(rest, ref)
    case Some{+info} <> rest: Bool.pick(Unit -> Maybe<&2, Hosted.GitHost>, projectHasAt(ref, info), _ => firstAccepted(rest, ref), _ => Some{info})(Unit{})

def firstHosted(+context: URL.Context, candidates: List<&2, String>, +repo: String, +ref: Maybe<&2, String>) -> Maybe<&2, Maybe<&2, GitSource>>:
  Maybe.map(&2, Hosted.GitHost, Maybe<&2, GitSource>, info => hostedSource(repo, ref, info), firstAccepted(hostedInfos(context, candidates), ref))

def nonEmptyList(url: String) -> List<&2, String>:
  match url:
    case SNil{}: Nil{}
    case other: other <> Nil{}

def withRef(+prefix: String, +repo: String, ref: Maybe<&2, String>, +url: String) -> List<&2, String>:
  match ref:
    case Some{value}: (prefix ++ repo ++ "#" ++ value) <> nonEmptyList(url)
    case None{}: nonEmptyList(url)

def hostedRepo(+repo: String) -> String:
  Bool.pick(String, explicitProtocol(repo) || String.starts_with(repo, "git@"), repo, "https://" ++ repo)

def httpsOrGeneric(+context: URL.Context, +url: String, +repo: String, +ref: Maybe<&2, String>, found: Maybe<&2, Maybe<&2, GitSource>>) -> Maybe<&2, GitSource>:
  match found:
    case Some{source}: source
    case None{}: Maybe.default(&2, Maybe<&2, GitSource>, firstHosted(context, withRef("https://", repo, ref, "https://" ++ url), "https://" ++ repo, ref), parseGenericGitUrl(context, url))

def hostedOrGeneric(+context: URL.Context, +url: String, split: Split) -> Maybe<&2, GitSource>:
  match split:
    case Split{+repo, +ref}: httpsOrGeneric(context, url, repo, ref, firstHosted(context, withRef("", repo, ref, url), hostedRepo(repo), ref))

def lowerScheme(text: String) -> String: Text.asciiLower(String.take(text, 8n))

# /^(https?|ssh|git):\/\//i
def protocolURL(+url: String) -> Bool:
  +head = lowerScheme(url)
  String.starts_with(head, "https://") || String.starts_with(head, "http://") || String.starts_with(head, "ssh://") || String.starts_with(head, "git://")

def prefixed(+context: URL.Context, hasGitPrefix: Bool, +url: String) -> Maybe<&2, GitSource>:
  Bool.pick(Unit -> Maybe<&2, GitSource>, hasGitPrefix || protocolURL(url), _ => hostedOrGeneric(context, url, splitRef(context, url)), _ => None{})(Unit{})

# With git: all historical shorthand forms; without it only protocol URLs.
def parseGitUrl(+context: URL.Context, source: String) -> Maybe<&2, GitSource>:
  +trimmed = Text.trim(source)
  +hasGitPrefix = String.starts_with(trimmed, "git:")
  prefixed(context, hasGitPrefix, Bool.pick(String, hasGitPrefix, Text.trim(String.drop(trimmed, 4n)), trimmed))
