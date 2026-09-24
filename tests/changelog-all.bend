import Base
import ../packages/coding-agent/src/utils/changelog.bend as C

# Every entry of a CHANGELOG.md with normalized links, joined as upstream's
# /changelog does before reversing (tests/changelog_check.py compares).
def linked(entry: C.ChangelogEntry) -> String:
  match entry:
    case C.ChangelogEntry{major,minor,patch,content}: C.normalizeChangelogLinks(content,C.entryVersion(C.ChangelogEntry{major,minor,patch,""}))
def normalized(entries: List<&2,C.ChangelogEntry>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: linked(entry) <> normalized(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    entries : List<&2,C.ChangelogEntry> <- C.parseChangelog("../pi-mono/packages/coding-agent/CHANGELOG.md")
    IO.print(String.join(normalized(entries),"\n\n"))
