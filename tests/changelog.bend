import Base
import ../packages/coding-agent/src/utils/changelog.bend as C

# upstream test/changelog.test.ts, plus parsing and new-entry selection.
def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def entry() -> C.ChangelogEntry: C.ChangelogEntry{0n,79n,0n,""}
def packageRelative() -> String:
  String.join(["[Project Trust](README.md#project-trust)","[Extensions](docs/extensions.md#project_trust)","[Examples](examples/extensions/)","[Root README](../../README.md#supply-chain-hardening)"],"\n")
def packageRelativeExpected() -> String:
  String.join(["[Project Trust](https://github.com/earendil-works/pi/blob/v0.79.0/packages/coding-agent/README.md#project-trust)","[Extensions](https://github.com/earendil-works/pi/blob/v0.79.0/packages/coding-agent/docs/extensions.md#project_trust)","[Examples](https://github.com/earendil-works/pi/tree/v0.79.0/packages/coding-agent/examples/extensions/)","[Root README](https://github.com/earendil-works/pi/blob/v0.79.0/README.md#supply-chain-hardening)"],"\n")
def legacy() -> String:
  String.join(["[#5167](https://github.com/earendil-works/pi-mono/pull/5167)","[#4163](https://github.com/badlogic/pi-mono/issues/4163)","[Agent README](https://github.com/badlogic/pi-mono/blob/main/packages/agent/README.md)","[External](https://example.com/docs)","[Local anchor](#settings)"],"\n")
def legacyExpected() -> String:
  String.join(["[#5167](https://github.com/earendil-works/pi/pull/5167)","[#4163](https://github.com/earendil-works/pi/issues/4163)","[Agent README](https://github.com/earendil-works/pi/blob/v0.79.0/packages/agent/README.md)","[External](https://example.com/docs)","[Local anchor](#settings)"],"\n")
def sample() -> String:
  "# Changelog\n\n## [Unreleased]\n\n- pending\n\n## [0.80.1] - 2026-01-02\n\n### Fixed\n\n- a [fix](docs/a b.md \"title\")\n\n## 0.80.0\n\n- first\n\n## [0.79.3]\n- older\n"
def versions(entries: List<&2,C.ChangelogEntry>) -> String:
  match entries:
    case Nil{}: ""
    case e <> rest: C.entryVersion(e) ++ ";" ++ versions(rest)
def contents(entries: List<&2,C.ChangelogEntry>) -> String:
  match entries:
    case Nil{}: ""
    case C.ChangelogEntry{_,_,_,content} <> rest: content ++ "|" ++ contents(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    check(String.eq(C.normalizeChangelogLinks(packageRelative(),C.entryVersion(entry())),packageRelativeExpected()),"rewrites package-relative changelog links to tag-pinned GitHub source links")
    check(String.eq(C.normalizeChangelogLinks(legacy(),"0.79.0"),legacyExpected()),"canonicalizes old repository URLs without changing external links")
    +parsed : List<&2,C.ChangelogEntry> <- IO.pure(List<&2,C.ChangelogEntry>,C.parseChangelogText(sample()))
    check(String.eq(versions(parsed),"0.80.1;0.80.0;0.79.3;"),"parses versioned headings and skips unreleased text")
    check(String.eq(contents(parsed),"## [0.80.1] - 2026-01-02\n\n### Fixed\n\n- a [fix](docs/a b.md \"title\")|## 0.80.0\n\n- first|## [0.79.3]\n- older|"),"entry content runs to the next heading, trimmed")
    check(String.eq(versions(C.getNewEntries(parsed,"0.80.0")),"0.80.1;"),"new entries are those after the last version")
    check(String.eq(versions(C.getNewEntries(parsed,"0.79")),"0.80.1;0.80.0;0.79.3;"),"missing version parts count as zero")
    check(String.eq(C.normalizeChangelogLinks("see ![img](docs/x y.png) and [a](docs/é.md)","v1.2.3"),"see ![img](https://github.com/earendil-works/pi/tree/v1.2.3/packages/coding-agent/docs/x y.png) and [a](https://github.com/earendil-works/pi/blob/v1.2.3/packages/coding-agent/docs/%C3%A9.md)"),"image links, titles after whitespace and encodeURI of the repository path (upstream output)")
    +real : List<&2,C.ChangelogEntry> <- C.parseChangelog("../pi-mono/packages/coding-agent/CHANGELOG.md")
    IO.print("real changelog entries: " ++ Nat.show(List.length(&2,C.ChangelogEntry,real)) ++ ", first " ++ versions(List.take(&2,C.ChangelogEntry,real,1n)))
