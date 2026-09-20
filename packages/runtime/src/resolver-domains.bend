import Base
import ./dns-presentation.bend as Presentation
import ./dns-search.bend as Search
import ./dns-name.bend as Name

type Issue is Data:
  Issue{position: Nat, text: String, error: Presentation.Error}

type Report is Data:
  Report{domains: List<&2, Search.Domain>, issues: List<&2, Issue>}

# The system search loop removes one leading dot before appending a suffix.
# Empty and "." both mean root. A remaining leading dot would create an
# empty label after the base name and must not become another root alias.
def withoutLeadingDot(text: String) -> String:
  match text:
    case SCon{'.', rest}: rest
    case other: other

def suffix(text: String) -> Result<&2, &2, Presentation.Error, Presentation.Parsed>:
  match text:
    case SCon{'.', _}: Fail{Presentation.EmptyLabel{}}
    case other: Presentation.parse(other)

def wireError(error: Presentation.Error) -> Name.Error:
  match error:
    case Presentation.InvalidByte{}: Name.InvalidByte{}
    case Presentation.RawNul{}: Name.InvalidByte{}
    case Presentation.NameTooLong{}: Name.NameTooLong{}
    case _: Name.InvalidLabel{}

def added(position: Nat, text: String, result: Result<&2, &2, Presentation.Error, Presentation.Parsed>, report: Report) -> Report:
  match result report:
    case Done{Presentation.Parsed{name, _}} Report{domains, issues}: Report{Search.Valid{name} <> domains, issues}
    case Fail{+error} Report{domains, issues}: Report{Search.Invalid{wireError(error)} <> domains, Issue{position, text, error} <> issues}

def collect(values: List<&2, String>, +position: Nat, report: Report) -> Report:
  match values report:
    case Nil{} Report{domains, issues}: Report{List.reverse(&2, Search.Domain, domains), List.reverse(&2, Issue, issues)}
    case +text <> rest previous: collect(rest, (position + 1n : Nat), added(position, text, suffix(withoutLeadingDot(text)), previous))

# Retain every entry, including duplicates and invalid suffixes. No query is
# issued here and no search option or error-recovery policy is inferred.
def prepare(values: List<&2, String>) -> Report:
  collect(values, 0n, Report{Nil{}, Nil{}})
