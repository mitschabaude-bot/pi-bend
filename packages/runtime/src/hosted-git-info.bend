import Base
import ./url.bend as URL
import ./uri-component.bend as URI
import ./text.bend as Text

# hosted-git-info 9.0.3 `fromUrl`: recognizes GitHub, Bitbucket, GitLab, Gist
# and Sourcehut repository URLs and shortcuts (github:user/repo, user/repo)
# and extracts their host, user, project and committish. pi reads only these
# fields; the library's URL templates (ssh(), https(), tarball(), ...) and its
# fromManifest/LRU cache are not ported. JavaScript object-key lookups become
# explicit tables, so inherited Object.prototype names are not host names.

type HostKind is Data:
  GitHub{}
  Bitbucket{}
  GitLab{}
  Gist{}
  Sourcehut{}

# `user` and `committish` keep hosted-git-info's null ("None") apart from the
# empty string; `defaultRepresentation` is the library's `default`.
type GitHost is Data:
  GitHost{kind: HostKind, domain: String, user: Maybe<&2, String>, auth: Maybe<&2, String>, project: String, committish: Maybe<&2, String>, defaultRepresentation: String}

def name(kind: HostKind) -> String:
  match kind:
    case GitHub{}: "github"
    case Bitbucket{}: "bitbucket"
    case GitLab{}: "gitlab"
    case Gist{}: "gist"
    case Sourcehut{}: "sourcehut"

def domainOf(kind: HostKind) -> String:
  match kind:
    case GitHub{}: "github.com"
    case Bitbucket{}: "bitbucket.org"
    case GitLab{}: "gitlab.com"
    case Gist{}: "gist.github.com"
    case Sourcehut{}: "git.sr.ht"

def protocols(kind: HostKind) -> List<&2, String>:
  match kind:
    case GitHub{}: "git:" <> "http:" <> "git+ssh:" <> "git+https:" <> "ssh:" <> "https:" <> Nil{}
    case Bitbucket{}: "git+ssh:" <> "git+https:" <> "ssh:" <> "https:" <> Nil{}
    case GitLab{}: "git+ssh:" <> "git+https:" <> "ssh:" <> "https:" <> Nil{}
    case Gist{}: "git:" <> "git+ssh:" <> "git+https:" <> "ssh:" <> "https:" <> Nil{}
    case Sourcehut{}: "git+ssh:" <> "https:" <> Nil{}

def byShortcut(protocol: String) -> Maybe<&2, HostKind>:
  match protocol:
    case "github:": Some{GitHub{}}
    case "bitbucket:": Some{Bitbucket{}}
    case "gitlab:": Some{GitLab{}}
    case "gist:": Some{Gist{}}
    case "sourcehut:": Some{Sourcehut{}}
    case _: None{}

def byDomain(domain: String) -> Maybe<&2, HostKind>:
  match domain:
    case "github.com": Some{GitHub{}}
    case "bitbucket.org": Some{Bitbucket{}}
    case "gitlab.com": Some{GitLab{}}
    case "gist.github.com": Some{Gist{}}
    case "git.sr.ht": Some{Sourcehut{}}
    case _: None{}

# The protocol table: known protocols, their representation projectName and whether
# credentials become `auth`.
type Protocol is Data:
  Protocol{representation: Maybe<&2, String>, auth: Bool}

def protocolInfo(protocol: String) -> Maybe<&2, Protocol>:
  match protocol:
    case "git+ssh:": Some{Protocol{Some{"sshurl"}, False{}}}
    case "ssh:": Some{Protocol{Some{"sshurl"}, False{}}}
    case "git+https:": Some{Protocol{Some{"https"}, True{}}}
    case "git:": Some{Protocol{None{}, True{}}}
    case "http:": Some{Protocol{None{}, True{}}}
    case "https:": Some{Protocol{None{}, True{}}}
    case "git+http:": Some{Protocol{None{}, True{}}}
    case +other: Maybe.map(&2, HostKind, Protocol, kind => Protocol{Some{name(kind)}, False{}}, byShortcut(other))

# String positions (JavaScript indexOf/lastIndexOf with -1 as None)
# ----------------

def indexFrom(text: String, +char: Char, +index: Nat) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: None{}
    case SCon{+head, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, Char.is_eq(head, char), _ => Some{index}, _ => indexFrom(rest, char, 1n+index))(Unit{})

def indexOf(text: String, +char: Char) -> Maybe<&2, Nat>: indexFrom(text, char, 0n)

def lastBefore(text: String, +char: Char, +limit: Maybe<&2, Nat>, +index: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: found
    case SCon{+head, rest}:
      +within = Maybe.default(&2, Bool, Maybe.map(&2, Nat, Bool, bound => Nat.is_le(index, bound), limit), True{})
      lastBefore(rest, char, limit, 1n+index, Bool.pick(Maybe<&2, Nat>, within && Char.is_eq(head, char), Some{index}, found))

# lastIndexOfBefore: the last `char` before the first `before` (anywhere when
# there is none).
def lastIndexOfBefore(+text: String, +char: Char, +before: Char) -> Maybe<&2, Nat>:
  lastBefore(text, char, indexOf(text, before), 0n, None{})

def spaceFrom(text: String, +index: Nat) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, Text.whitespace(code), _ => Some{index}, _ => spaceFrom(rest, 1n+index))(Unit{})

def charAt(text: String, index: Nat) -> Maybe<&2, Char>:
  match text index:
    case SNil{} _: None{}
    case SCon{head, _} 0n: Some{head}
    case SCon{_, rest} 1n+previous: charAt(rest, previous)

def isGreater(value: Maybe<&2, Nat>, +than: Maybe<&2, Nat>) -> Bool:
  match value than:
    case Some{left} Some{right}: Nat.is_gt(left, right)
    case Some{_} None{}: True{}
    case None{} _: False{}

# `x === -1 || (firstHash > -1 && x > firstHash)`
def onlyAfterHash(value: Maybe<&2, Nat>, +hash: Maybe<&2, Nat>) -> Bool:
  match value hash:
    case None{} _: True{}
    case Some{index} Some{at}: Nat.is_gt(index, at)
    case Some{_} None{}: False{}

def secondSlash(+text: String, first: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match first:
    case None{}: indexOf(text, '/')
    case Some{+index}: Maybe.map(&2, Nat, Nat, offset => Nat.add(Nat.add(index, 1n), offset), indexOf(String.drop(text, 1n+index), '/'))

def notSlashBeforeHash(+text: String, hash: Maybe<&2, Nat>) -> Bool:
  match hash:
    case None{}: Bool.not(String.ends_with(text, "/"))
    case Some{0n}: True{}
    case Some{1n+previous}: Bool.not(Maybe.default(&2, Bool, Maybe.map(&2, Char, Bool, char => Char.is_eq(char, '/'), charAt(text, previous)), False{}))

def slashAfterStart(first: Maybe<&2, Nat>) -> Bool:
  match first:
    case Some{1n+_}: True{}
    case _: False{}

# GitHub shorthand such as npm/cli: a slash (not first, and no second one), no
# whitespace, @ or : before any #, no trailing slash and no leading dot.
def isGitHubShorthand(+arg: String) -> Bool:
  +hash = indexOf(arg, '#')
  +slash = indexOf(arg, '/')
  onlyAfterHash(spaceFrom(arg, 0n), hash) && slashAfterStart(slash) && notSlashBeforeHash(arg, hash) && Bool.not(String.starts_with(arg, ".")) && onlyAfterHash(indexOf(arg, '@'), hash) && onlyAfterHash(indexOf(arg, ':'), hash) && onlyAfterHash(secondSlash(arg, slash), hash)

# parse-url.js
# ------------

def through(text: String, index: Nat) -> String: String.take(text, 1n+index)

def isProtocolKey(+protocol: String) -> Bool: Maybe.is_some(&2, Protocol, protocolInfo(protocol))

def slashesAfterColon(+arg: String, colon: Maybe<&2, Nat>) -> String:
  match colon:
    case Some{+position}: through(arg, position) ++ "//" ++ String.drop(arg, 1n+position)
    case None{}: "//" ++ arg

def withAt(+arg: String, +colon: Maybe<&2, Nat>, at: Maybe<&2, Nat>) -> String:
  match at:
    case Some{index}: Bool.pick(String, isGreater(Some{index}, colon), "git+ssh://" ++ arg, arg)
    case None{}: slashesAfterColon(arg, colon)

# correctProtocol: git:github.com:user/repo gains the // after its first colon.
def correctProtocol(+arg: String) -> String:
  +colon = indexOf(arg, ':')
  +proto = Maybe.default(&2, String, Maybe.map(&2, Nat, String, index => through(arg, index), colon), "")
  +authority = Maybe.default(&2, Bool, Maybe.map(&2, Nat, Bool, index => String.starts_with(String.drop(arg, index), "://"), colon), False{})
  Bool.pick(Unit -> String, isProtocolKey(proto) || authority, _ => arg, _ => withAt(arg, colon, indexOf(arg, '@')))(Unit{})

def replacedColon(+text: String, colon: Maybe<&2, Nat>, +at: Maybe<&2, Nat>) -> String:
  match colon:
    case Some{+index}: Bool.pick(String, isGreater(Some{index}, at), String.take(text, index) ++ "/" ++ String.drop(text, 1n+index), text)
    case None{}: text

def sshPrefixed(+text: String) -> String:
  +bare = Maybe.is_none(&2, Nat, lastIndexOfBefore(text, ':', '#')) && Bool.not(String.contains(text, "//"))
  Bool.pick(String, bare, "git+ssh://" ++ text, text)

# correctUrl: an scp-style URL's last colon (after its @) becomes a slash; a
# URL with no colon at all gains git+ssh://.
def correctUrl(+giturl: String) -> String:
  sshPrefixed(replacedColon(giturl, lastIndexOfBefore(giturl, ':', '#'), lastIndexOfBefore(giturl, '@', '#')))

def okUrl(result: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, URL.URL>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def safeUrl(context: URL.Context, text: String) -> Maybe<&2, URL.URL>: okUrl(URL.parse(context, text))

def parseUrl(+context: URL.Context, giturl: String) -> Maybe<&2, URL.URL>:
  +withProtocol = correctProtocol(giturl)
  Maybe.or(&2, URL.URL, safeUrl(context, withProtocol), safeUrl(context, correctUrl(withProtocol)))

# Host extraction
# ---------------

type Segments is Data:
  Segments{user: Maybe<&2, String>, project: String, committish: String}

def withoutGit(+project: String) -> String:
  Bool.pick(String, String.ends_with(project, ".git"), String.take(project, Nat.sub(String.length(project), 4n)), project)

# JavaScript's String.split('/', limit) as optional fields.
def part(parts: List<&2, String>, index: Nat) -> Maybe<&2, String>:
  match parts index:
    case Nil{} _: None{}
    case head <> _ 0n: Some{head}
    case _ <> rest 1n+previous: part(rest, previous)

def truthy(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: True{}
    case _: False{}

def hashValue(+url: URL.URL) -> String: String.drop(URL.hash(url), 1n)

def pathParts(+url: URL.URL) -> List<&2, String>: String.split(URL.pathname(url), '/')

def userProject(user: Maybe<&2, String>, project: Maybe<&2, String>, committish: String) -> Maybe<&2, Segments>:
  match user project:
    case Some{SCon{+u, +us}} Some{+projectName}: Bool.pick(Maybe<&2, Segments>, truthy(Some{withoutGit(projectName)}), Some{Segments{Some{SCon{u, us}}, withoutGit(projectName), committish}}, None{})
    case _ _: None{}

# github: /user/project[/tree/committish], else the hash. A tree URL without
# its committish yields the committish "undefined", as the library does.
def githubCommittish(+url: URL.URL, kind: Maybe<&2, String>, committish: Maybe<&2, String>) -> Maybe<&2, String>:
  match kind committish:
    case None{} _: Some{hashValue(url)}
    case Some{SNil{}} _: Some{hashValue(url)}
    case Some{"tree"} Some{value}: Some{value}
    case Some{"tree"} None{}: Some{"undefined"}
    case Some{_} _: None{}

def githubSegments(+parts: List<&2, String>, committish: Maybe<&2, String>) -> Maybe<&2, Segments>:
  match committish:
    case None{}: None{}
    case Some{value}: userProject(part(parts, 1n), part(parts, 2n), value)

def extractGitHub(+url: URL.URL) -> Maybe<&2, Segments>:
  +parts = pathParts(url)
  githubSegments(parts, githubCommittish(url, part(parts, 3n), part(parts, 4n)))

def excludedAux(+parts: List<&2, String>, +aux: String) -> Bool:
  Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, value => String.eq(value, aux), part(parts, 3n)), False{})

def extractSimple(+url: URL.URL, +aux: String) -> Maybe<&2, Segments>:
  +parts = pathParts(url)
  Bool.pick(Unit -> Maybe<&2, Segments>, excludedAux(parts, aux), _ => None{}, _ => userProject(part(parts, 1n), part(parts, 2n), hashValue(url)))(Unit{})

def gitlabSegments(reversed: List<&2, String>, committish: String) -> Maybe<&2, Segments>:
  match reversed:
    case Nil{}: None{}
    case project <> rest: userProject(Some{String.join(List.reverse(&2, String, rest), "/")}, Some{project}, committish)

def extractGitLab(+url: URL.URL) -> Maybe<&2, Segments>:
  +path = String.drop(URL.pathname(url), 1n)
  Bool.pick(Unit -> Maybe<&2, Segments>, String.contains(path, "/-/") || String.contains(path, "/archive.tar.gz"), _ => None{}, _ => gitlabSegments(List.reverse(&2, String, String.split(path, '/')), hashValue(url)))(Unit{})

def gistSegments(user: Maybe<&2, String>, project: Maybe<&2, String>, committish: String) -> Maybe<&2, Segments>:
  match user project:
    case Some{projectName} Some{SCon{p, ps}}: Some{Segments{Some{projectName}, withoutGit(SCon{p, ps}), committish}}
    case Some{SCon{u, us}} _: Some{Segments{None{}, withoutGit(SCon{u, us}), committish}}
    case _ _: None{}

def extractGist(+url: URL.URL) -> Maybe<&2, Segments>:
  +parts = pathParts(url)
  Bool.pick(Unit -> Maybe<&2, Segments>, excludedAux(parts, "raw"), _ => None{}, _ => gistSegments(part(parts, 1n), part(parts, 2n), hashValue(url)))(Unit{})

def extract(+kind: HostKind, +url: URL.URL) -> Maybe<&2, Segments>:
  match kind:
    case GitHub{}: extractGitHub(url)
    case Bitbucket{}: extractSimple(url, "get")
    case GitLab{}: extractGitLab(url)
    case Gist{}: extractGist(url)
    case Sourcehut{}: extractSimple(url, "archive")

# from-url.js
# -----------

def withoutWww(+hostname: String) -> String:
  Bool.pick(String, String.starts_with(hostname, "www."), String.drop(hostname, 4n), hostname)

def Protocol.auth(info: Protocol) -> Bool:
  match info:
    case Protocol{_, auth}: auth

def authOf(+url: URL.URL) -> Maybe<&2, String>:
  +username = URL.usernameOf(url)
  +password = URL.passwordOf(url)
  +allowed = Maybe.default(&2, Bool, Maybe.map(&2, Protocol, Bool, info => Protocol.auth(info), protocolInfo(URL.protocol(url))), False{})
  Bool.pick(Maybe<&2, String>, allowed && (Bool.not(String.is_empty(username)) || Bool.not(String.is_empty(password))), Some{username ++ Bool.pick(String, String.is_empty(password), "", ":" ++ password)}, None{})

def dropThrough(+path: String, at: Maybe<&2, Nat>) -> String:
  match at:
    case Some{index}: String.drop(path, 1n+index)
    case None{}: path

def afterAt(+path: String) -> String: dropThrough(path, indexOf(path, '@'))

def lastSlash(text: String, +index: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: found
    case SCon{'/', rest}: lastSlash(rest, 1n+index, Some{index})
    case SCon{_, rest}: lastSlash(rest, 1n+index, found)

def nonEmpty(value: String) -> Maybe<&2, String>:
  match value:
    case SNil{}: None{}
    case other: Some{other}

def decodedCommittish(+hash: String) -> Maybe<&2, Maybe<&2, String>>:
  match hash:
    case SNil{}: Some{None{}}
    case SCon{_, rest}: Maybe.map(&2, String, Maybe<&2, String>, value => Some{value}, URI.decode(rest))

def shortcutHost(+kind: HostKind, +url: URL.URL, auth: Maybe<&2, String>, user: Maybe<&2, String>, project: Maybe<&2, String>, committish: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, GitHost>:
  match project committish:
    case Some{projectName} Some{hash}: Some{GitHost{kind, domainOf(kind), user, auth, withoutGit(projectName), hash, "shortcut"}}
    case _ _: None{}

def splitUser(+pathname: String, slash: Maybe<&2, Nat>) -> Maybe<&2, Maybe<&2, String>> & Maybe<&2, String>:
  match slash:
    case Some{+index}: (Maybe.map(&2, String, Maybe<&2, String>, nonEmpty, URI.decode(String.take(pathname, index))), URI.decode(String.drop(pathname, 1n+index)))
    case None{}: (Some{None{}}, URI.decode(pathname))

def shortcutParts(+kind: HostKind, +url: URL.URL, auth: Maybe<&2, String>, parts: Maybe<&2, Maybe<&2, String>> & Maybe<&2, String>) -> Maybe<&2, GitHost>:
  match parts:
    case (Some{user}, project): shortcutHost(kind, url, auth, user, project, decodedCommittish(URL.hash(url)))
    case (None{}, _): None{}

def shortcut(+kind: HostKind, +url: URL.URL, auth: Maybe<&2, String>) -> Maybe<&2, GitHost>:
  +path = URL.pathname(url)
  +pathname = afterAt(Bool.pick(String, String.starts_with(path, "/"), String.drop(path, 1n), path))
  shortcutParts(kind, url, auth, splitUser(pathname, lastSlash(pathname, 0n, None{})))

def decodedUser(user: Maybe<&2, String>) -> Maybe<&2, Maybe<&2, String>>:
  match user:
    case Some{SCon{u, us}}: Maybe.map(&2, String, Maybe<&2, String>, value => Some{value}, URI.decode(SCon{u, us}))
    case other: Some{other}

def segmentHost(+kind: HostKind, auth: Maybe<&2, String>, representation: String, user: Maybe<&2, Maybe<&2, String>>, project: Maybe<&2, String>, committish: Maybe<&2, String>) -> Maybe<&2, GitHost>:
  match user project committish:
    case Some{projectName} Some{value} Some{hash}: Some{GitHost{kind, domainOf(kind), projectName, auth, value, Some{hash}, representation}}
    case _ _ _: None{}

def segmentsHost(+kind: HostKind, auth: Maybe<&2, String>, representation: String, segments: Maybe<&2, Segments>) -> Maybe<&2, GitHost>:
  match segments:
    case None{}: None{}
    case Some{Segments{user, project, committish}}: segmentHost(kind, auth, representation, decodedUser(user), URI.decode(project), URI.decode(committish))

def representationFrom(+protocol: String, info: Maybe<&2, Protocol>) -> String:
  match info:
    case Some{Protocol{Some{representation}, _}}: representation
    case _: String.take(protocol, Nat.sub(String.length(protocol), 1n))

def representationOf(+protocol: String) -> String: representationFrom(protocol, protocolInfo(protocol))

def listed(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: String.eq(head, value) || listed(rest, value)

def domainHost(+kind: HostKind, +url: URL.URL, auth: Maybe<&2, String>) -> Maybe<&2, GitHost>:
  +protocol = URL.protocol(url)
  Bool.pick(Unit -> Maybe<&2, GitHost>, listed(protocols(kind), protocol), _ => segmentsHost(kind, auth, representationOf(protocol), extract(kind, url)), _ => None{})(Unit{})

def recognized(shortcutKind: Maybe<&2, HostKind>, domainKind: Maybe<&2, HostKind>, +url: URL.URL) -> Maybe<&2, GitHost>:
  match shortcutKind domainKind:
    case Some{kind} _: shortcut(kind, url, authOf(url))
    case None{} Some{kind}: domainHost(kind, url, authOf(url))
    case None{} None{}: None{}

def parsed(url: Maybe<&2, URL.URL>) -> Maybe<&2, GitHost>:
  match url:
    case None{}: None{}
    case Some{+value}: recognized(byShortcut(URL.protocol(value)), byDomain(withoutWww(URL.hostname(value))), value)

# GitHost.fromUrl
def fromUrl(+context: URL.Context, giturl: String) -> Maybe<&2, GitHost>:
  match giturl:
    case SNil{}: None{}
    case +text: parsed(parseUrl(context, Bool.pick(String, isGitHubShorthand(text), "github:" ++ text, text)))
