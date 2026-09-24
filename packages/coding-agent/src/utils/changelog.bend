import Base
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/url.bend as Url
import ../../../runtime/src/utf8.bend as Utf8

# upstream utils/changelog.ts: CHANGELOG.md entries and their links, pinned to
# the release tag on GitHub.
type ChangelogEntry is Data: ChangelogEntry{major: Nat,minor: Nat,patch: Nat,content: String}

def GITHUB_REPO() -> String: "earendil-works/pi"
def CHANGELOG_LINK_BASE_PATH() -> String: "packages/coding-agent"
def repoUrl() -> String: "https://github.com/" ++ GITHUB_REPO()

def entryVersion(entry: ChangelogEntry) -> String:
  match entry:
    case ChangelogEntry{major,minor,patch,_}: Nat.show(major) ++ "." ++ Nat.show(minor) ++ "." ++ Nat.show(patch)

# A version string or an entry's version, as a `v`-prefixed tag.
def normalizeTag(+version: String) -> String: Bool.pick(String,String.starts_with(version,"v"),version,"v" ++ version)

# upstream LEGACY_REPO_RE: the old pi-mono repository, at its end or before a `/`.
def legacyTail(rest: String) -> Maybe<&2,String>:
  match rest:
    case SNil{}: Some{""}
    case SCon{'/',_}: Some{rest}
    case _: None{}
def legacyAfter(prefixed: Bool,target: String,+prefix: String) -> Maybe<&2,String>:
  match prefixed:
    case False{}: None{}
    case True{}: legacyTail(String.drop(target,String.length(prefix)))
def legacyRest(+target: String,+prefix: String) -> Maybe<&2,String>: legacyAfter(String.starts_with(target,prefix),target,prefix)
def legacyCanonical(+target: String,badlogic: Maybe<&2,String>,earendil: Maybe<&2,String>) -> String:
  match badlogic earendil:
    case Some{rest} _: repoUrl() ++ rest
    case _ Some{rest}: repoUrl() ++ rest
    case _ _: target
def canonicalRepo(+target: String) -> String:
  legacyCanonical(target,legacyRest(target,"https://github.com/badlogic/pi-mono"),legacyRest(target,"https://github.com/earendil-works/pi-mono"))

def tagRoute(route: String) -> String:
  match route:
    case SCon{'b',SCon{'l',_}}: "blob"
    case _: "tree"
# Floating `blob|tree/main|master/` links are pinned to the release tag.
def pinnedRef(routes: List<&2,String>,+target: String,+tag: String) -> String:
  match routes:
    case Nil{}: target
    case +route <> rest:
      +prefix = repoUrl() ++ "/" ++ route ++ "/"
      pinnedRef(rest,Bool.pick(String,String.starts_with(target,prefix),repoUrl() ++ "/" ++ tagRoute(route) ++ "/" ++ tag ++ "/" ++ String.drop(target,String.length(prefix)),target),tag)

# upstream URL_SCHEME_RE: /^[a-z][a-z0-9+.-]*:/i
def asciiLetter(+code: U32) -> Bool: (U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,97) && U32.is_le(code,122))
def schemeChar(+code: U32) -> Bool: asciiLetter(code) || (U32.is_ge(code,48) && U32.is_le(code,57)) || U32.is_eq(code,43) || U32.is_eq(code,45) || U32.is_eq(code,46)
def schemeRest(text: String) -> Bool:
  match text:
    case SCon{':',_}: True{}
    case SCon{Chr{+code},rest}: schemeChar(code) && schemeRest(rest)
    case SNil{}: False{}
def hasScheme(text: String) -> Bool:
  match text:
    case SCon{Chr{+code},rest}: asciiLetter(code) && schemeRest(rest)
    case SNil{}: False{}
def external(+target: String) -> Bool:
  String.starts_with(target,"#") || String.starts_with(target,"//") || hasScheme(target)

# upstream splitLocalTarget: path, then `?query`, then `#fragment`.
type LocalTarget is Data: LocalTarget{pathPart: String,query: String,fragment: String}
def fragmentSplit(text: String,+reversed: String) -> String & String:
  match text:
    case SNil{}: (String.reverse(reversed),"")
    case SCon{'#',_}: (String.reverse(reversed),text)
    case SCon{char,rest}: fragmentSplit(rest,SCon{char,reversed})
def querySplit(text: String,+reversed: String) -> String & String:
  match text:
    case SNil{}: (String.reverse(reversed),"")
    case SCon{'?',_}: (String.reverse(reversed),text)
    case SCon{char,rest}: querySplit(rest,SCon{char,reversed})
def withFragment(pair: String & String,fragment: String) -> LocalTarget:
  match pair:
    case (pathPart,query): LocalTarget{pathPart,query,fragment}
def localParts(pair: String & String) -> LocalTarget:
  match pair:
    case (beforeHash,fragment): withFragment(querySplit(beforeHash,""),fragment)
def splitLocalTarget(target: String) -> LocalTarget: localParts(fragmentSplit(target,""))

def slashes(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\\',rest}: slashes(rest,SCon{'/',reversed})
    case SCon{char,rest}: slashes(rest,SCon{char,reversed})
def leadingSlashes(text: String) -> String:
  match text:
    case SCon{'/',rest}: leadingSlashes(rest)
    case _: text
def insideRepository(+joined: String) -> Maybe<&2,String>:
  Bool.pick(Maybe<&2,String>,String.eq(joined,".") || String.eq(joined,"..") || String.starts_with(joined,"../"),None{},Some{joined})
def repositoryPathOf(normalized: String) -> Maybe<&2,String>:
  match normalized:
    case SCon{'/',rest}: insideRepository(Path.normalize(leadingSlashes(rest)))
    case relative: insideRepository(Path.join(CHANGELOG_LINK_BASE_PATH(),relative))
def resolveRepositoryPath(targetPath: String) -> Maybe<&2,String>: repositoryPathOf(slashes(targetPath,""))

def isDirectoryTarget(+originalPath: String,repositoryPath: String) -> Bool:
  String.ends_with(originalPath,"/") || Bool.not(String.contains(Path.basename(repositoryPath),"."))
def repositoryLink(repositoryPath: Maybe<&2,String>,+target: String,local: LocalTarget,tag: String) -> String:
  match repositoryPath local:
    case None{} _: target
    case Some{+path} LocalTarget{pathPart,query,fragment}:
      repoUrl() ++ "/" ++ Bool.pick(String,isDirectoryTarget(pathPart,path),"tree","blob") ++ "/" ++ tag ++ "/" ++ Url.encode(Url.EcmaUri{},path) ++ query ++ fragment
def localLink(+target: String,local: LocalTarget,tag: String) -> String:
  match local:
    case LocalTarget{SNil{},_,_}: target
    case LocalTarget{+pathPart,query,fragment}: repositoryLink(resolveRepositoryPath(pathPart),target,LocalTarget{pathPart,query,fragment},tag)
def normalizedTarget(+target: String,tag: String) -> String:
  Bool.pick(Unit -> String,external(target),_ => target,_ => localLink(target,splitLocalTarget(target),tag))(Unit{})
def normalizeChangelogLinkTarget(target: String,+tag: String) -> String:
  normalizedTarget(pinnedRef(["blob/main","blob/master","tree/main","tree/master"],canonicalRepo(target),tag),tag)

# upstream INLINE_MARKDOWN_LINK_RE, /(!?\[[^\]\n]+\]\()([^\s)]+)((?:\s+[^)]*)?\))/g:
# the link target is rewritten; the label and title are kept.
type Link is Data: Link{prefix: String,target: String,suffix: String,rest: String}
type Tail is Data: Tail{text: String,rest: String}
def closing(text: String,+reversed: String) -> Maybe<&2,Tail>:
  match text:
    case SNil{}: None{}
    case SCon{')',rest}: Some{Tail{String.reverse(SCon{')',reversed}),rest}}
    case SCon{char,rest}: closing(rest,SCon{char,reversed})
def suffixAt(text: String) -> Maybe<&2,Tail>:
  match text:
    case SCon{')',rest}: Some{Tail{")",rest}}
    case SCon{Chr{+code},rest}: Bool.pick(Unit -> Maybe<&2,Tail>,Text.whitespace(code),_ => closing(rest,SCon{Chr{code},""}),_ => None{})(Unit{})
    case SNil{}: None{}
def linked(prefix: String,+target: String,suffix: Maybe<&2,Tail>) -> Maybe<&2,Link>:
  match suffix:
    case None{}: None{}
    case Some{Tail{tail,rest}}: Some{Link{prefix,target,tail,rest}}
def targetChar(+code: U32) -> Bool: Bool.not(Text.whitespace(code) || U32.is_eq(code,41))
def targetScan(text: String,+prefix: String,+reversed: String) -> Maybe<&2,Link>:
  match text:
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> Maybe<&2,Link>,targetChar(code),
        _ => targetScan(rest,prefix,SCon{Chr{code},reversed}),
        _ => Bool.pick(Unit -> Maybe<&2,Link>,String.is_empty(reversed),_ => None{},_ => linked(prefix,String.reverse(reversed),suffixAt(SCon{Chr{code},rest})))(Unit{}))(Unit{})
    case SNil{}: None{}
def labelScan(text: String,+reversed: String) -> Maybe<&2,Link>:
  match text:
    case SCon{']',SCon{'(',rest}}: Bool.pick(Unit -> Maybe<&2,Link>,String.is_empty(reversed),_ => None{},_ => targetScan(rest,String.reverse(SCon{'(',SCon{']',reversed}}),""))(Unit{})
    case SCon{']',_}: None{}
    case SCon{'\n',_}: None{}
    case SCon{char,rest}: labelScan(rest,SCon{char,reversed})
    case SNil{}: None{}
def withOpener(opener: String,link: Maybe<&2,Link>) -> Maybe<&2,Link>:
  match link:
    case Some{Link{prefix,target,suffix,rest}}: Some{Link{opener ++ prefix,target,suffix,rest}}
    case None{}: None{}
def linkAt(text: String) -> Maybe<&2,Link>:
  match text:
    case SCon{'!',SCon{'[',rest}}: withOpener("![",labelScan(rest,""))
    case SCon{'[',rest}: withOpener("[",labelScan(rest,""))
    case _: None{}
def prependReversed(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char,rest}: prependReversed(rest,SCon{char,reversed})
@unsafe
def linksFrom(text: String,found: Maybe<&2,Link>,+tag: String,reversed: String) -> String:
  match text found:
    case _ Some{Link{prefix,target,suffix,+rest}}: linksFrom(rest,linkAt(rest),tag,prependReversed(prefix ++ normalizeChangelogLinkTarget(target,tag) ++ suffix,reversed))
    case SNil{} None{}: String.reverse(reversed)
    case SCon{char,+rest} None{}: linksFrom(rest,linkAt(rest),tag,SCon{char,reversed})
def normalizeChangelogLinks(+markdown: String,version: String) -> String:
  linksFrom(markdown,linkAt(markdown),normalizeTag(version),"")

type Digits is Data: Digits{value: Nat,rest: String}
# upstream parseChangelog: `## [x.y.z]` headings open entries; text before the
# first version and under unversioned headings is skipped.
def digitsFrom(text: String,+value: Nat,+count: Nat) -> Maybe<&2,Digits>:
  match text:
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> Maybe<&2,Digits>,U32.is_ge(code,48) && U32.is_le(code,57),
        _ => digitsFrom(rest,value * 10n + U32.to_nat((code - 48 : U32)),count + 1n),
        _ => Bool.pick(Maybe<&2,Digits>,Nat.is_gt(count,0n),Some{Digits{value,SCon{Chr{code},rest}}},None{}))(Unit{})
    case SNil{}: Bool.pick(Maybe<&2,Digits>,Nat.is_gt(count,0n),Some{Digits{value,""}},None{})
def dotted(value: Maybe<&2,Digits>) -> Maybe<&2,Digits>:
  match value:
    case Some{Digits{number,SCon{'.',rest}}}: Some{Digits{number,rest}}
    case _: None{}
def patchOf(major: Nat,minor: Nat,value: Maybe<&2,Digits>) -> Maybe<&2,ChangelogEntry>:
  match value:
    case Some{Digits{patch,_}}: Some{ChangelogEntry{major,minor,patch,""}}
    case None{}: None{}
def minorOf(major: Nat,value: Maybe<&2,Digits>) -> Maybe<&2,ChangelogEntry>:
  match value:
    case Some{Digits{minor,rest}}: patchOf(major,minor,digitsFrom(rest,0n,0n))
    case None{}: None{}
def majorOf(value: Maybe<&2,Digits>) -> Maybe<&2,ChangelogEntry>:
  match value:
    case Some{Digits{major,rest}}: minorOf(major,dotted(digitsFrom(rest,0n,0n)))
    case None{}: None{}
def spaces(text: String,+count: Nat) -> Maybe<&2,String>:
  match text:
    case SCon{Chr{+code},+rest}: Bool.pick(Unit -> Maybe<&2,String>,Text.whitespace(code),_ => spaces(rest,count + 1n),_ => Bool.pick(Maybe<&2,String>,Nat.is_gt(count,0n),Some{SCon{Chr{code},rest}},None{}))(Unit{})
    case SNil{}: None{}
def bracketed(text: Maybe<&2,String>) -> Maybe<&2,ChangelogEntry>:
  match text:
    case Some{SCon{'[',rest}}: majorOf(dotted(digitsFrom(rest,0n,0n)))
    case Some{rest}: majorOf(dotted(digitsFrom(rest,0n,0n)))
    case None{}: None{}
# The `##\s+\[?(\d+)\.(\d+)\.(\d+)` match, anywhere in the heading: `found`
# is the match at the current position.
def versionAt(text: String) -> Maybe<&2,ChangelogEntry>:
  match text:
    case SCon{'#',SCon{'#',rest}}: bracketed(spaces(rest,0n))
    case _: None{}
def headingScan(text: String,found: Maybe<&2,ChangelogEntry>) -> Maybe<&2,ChangelogEntry>:
  match text found:
    case _ Some{entry}: Some{entry}
    case SNil{} None{}: None{}
    case SCon{_,+rest} None{}: headingScan(rest,versionAt(rest))
def headingVersion(+text: String) -> Maybe<&2,ChangelogEntry>: headingScan(text,versionAt(text))

type Parse is Data: Parse{entries: List<&2,ChangelogEntry>,current: Maybe<&2,ChangelogEntry>,lines: List<&2,String>}
def closed(current: Maybe<&2,ChangelogEntry>,lines: List<&2,String>,entries: List<&2,ChangelogEntry>) -> List<&2,ChangelogEntry>:
  match current lines:
    case Some{ChangelogEntry{major,minor,patch,_}} _ <> _: ChangelogEntry{major,minor,patch,Text.trim(String.join(List.reverse(&2,String,lines),"\n"))} <> entries
    case _ _: entries
def opened(+line: String,version: Maybe<&2,ChangelogEntry>,entries: List<&2,ChangelogEntry>) -> Parse:
  match version:
    case Some{entry}: Parse{entries,Some{entry},line <> Nil{}}
    case None{}: Parse{entries,None{},Nil{}}
def parseLine(state: Parse,+line: String) -> Parse:
  match state:
    case Parse{+entries,+current,+lines}:
      Bool.pick(Unit -> Parse,String.starts_with(line,"## "),
        _ => opened(line,headingVersion(line),closed(current,lines,entries)),
        _ => Bool.pick(Parse,Maybe.is_some(&2,ChangelogEntry,current),Parse{entries,current,line <> lines},Parse{entries,current,lines}))(Unit{})
def parseLines(lines: List<&2,String>,state: Parse) -> List<&2,ChangelogEntry>:
  match lines state:
    case Nil{} Parse{entries,current,collected}: List.reverse(&2,ChangelogEntry,closed(current,collected,entries))
    case line <> rest state: parseLines(rest,parseLine(state,line))
def parseChangelogText(content: String) -> List<&2,ChangelogEntry>:
  parseLines(Strings.split(content,'\n'),Parse{Nil{},None{},Nil{}})

# A missing or unreadable changelog has no entries.
def readEntries(read: Result<&2,&2,FS.Error,List<&2,U32>>) -> List<&2,ChangelogEntry>:
  match read:
    case Done{bytes}: parseChangelogText(Utf8.decodeBuffer(bytes))
    case Fail{_}: Nil{}
def parseChangelog(changelogPath: String) -> IO(List<&2,ChangelogEntry>):
  do IO<List<&2,ChangelogEntry>>:
    read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(changelogPath)
    return readEntries(read)

def compareVersions(v1: ChangelogEntry,v2: ChangelogEntry) -> Cmp:
  match v1 v2:
    case ChangelogEntry{+a,+b,+c,_} ChangelogEntry{+x,+y,+z,_}:
      Bool.pick(Cmp,Nat.is_eq(a,x),Bool.pick(Cmp,Nat.is_eq(b,y),Nat.cmp(c,z),Nat.cmp(b,y)),Nat.cmp(a,x))

# upstream getNewEntries: `lastVersion` split on dots; missing or non-numeric
# parts count as 0 (JavaScript `Number(part) || 0` for decimal digits).
def wholeNumber(value: Maybe<&2,Digits>) -> Nat:
  match value:
    case Some{Digits{number,SNil{}}}: number
    case _: 0n
def numberPart(value: Maybe<&2,String>) -> Nat:
  match value:
    case Some{text}: wholeNumber(digitsFrom(Text.trim(text),0n,0n))
    case None{}: 0n
def part(parts: List<&2,String>,index: Nat) -> Nat: numberPart(List.get(&2,String,parts,index))
def newer(entries: List<&2,ChangelogEntry>,+last: ChangelogEntry) -> List<&2,ChangelogEntry>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = newer(rest,last)
      Bool.pick(List<&2,ChangelogEntry>,Cmp.is_gt(compareVersions(entry,last)),entry <> tail,tail)
def getNewEntries(entries: List<&2,ChangelogEntry>,+lastVersion: String) -> List<&2,ChangelogEntry>:
  +parts = Strings.split(lastVersion,'.')
  newer(entries,ChangelogEntry{part(parts,0n),part(parts,1n),part(parts,2n),""})
