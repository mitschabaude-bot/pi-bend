import Base
import ./resolver-config.bend as Config
import ./resolver-settings.bend as Settings

type Values is Data:
  Values{localDomain: Maybe<&2, String>, options: Maybe<&2, String>}

type Error is Data:
  Error{variable: String, code: U32, message: String}

def failed(variable: String, code: U32, message: String, missing: Bool) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match missing:
    case True{}: Done{None{}}
    case False{}: Fail{Error{variable, code, message}}

# The current Linux and JS get_env primitives use ENOENT (2) for absence.
# Keep this platform classification at the boundary; other errors survive.
def normalized(variable: String, result: Result<&1, &1, U32 & String, String>) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match result:
    case Done{text}: Done{Some{text}}
    case Fail{(+code, message)}: failed(variable, code, message, U32.is_eq(code, 2))

def combined(local: Result<&2, &2, Error, Maybe<&2, String>>, options: Result<&2, &2, Error, Maybe<&2, String>>) -> Result<&2, &2, Error, Values>:
  match local options:
    case Fail{error} _: Fail{error}
    case Done{_} Fail{error}: Fail{error}
    case Done{domain} Done{tokens}: Done{Values{domain, tokens}}

# Both names are fixed and valid environment keys. The caller owns an injected
# lookup environment. Each variable is read once, in the order shown.
def captureWith(~Environment: Data, ~lookup: Environment -> String -> IO(Result<&1, &1, U32 & String, String>), +environment: Environment) -> IO(Result<&2, &2, Error, Values>):
  do IO<Result<&2, &2, Error, Values>>:
    local : Result<&1, &1, U32 & String, String> <- lookup(environment, "LOCALDOMAIN")
    options : Result<&1, &1, U32 & String, String> <- lookup(environment, "RES_OPTIONS")
    return combined(normalized("LOCALDOMAIN", local), normalized("RES_OPTIONS", options))

def lookup(unused: Unit, name: String) -> IO(Result<&1, &1, U32 & String, String>):
  IO.get_env(name)

def capture() -> IO(Result<&2, &2, Error, Values>):
  captureWith(~Unit, ~lookup, Unit{})

# LOCALDOMAIN ends at the first newline. An initial empty field denotes the
# root suffix and must survive: it can put a bare-name query before other suffixes.
def firstLine(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\n', _}: String.reverse(reversed)
    case SCon{char, rest}: firstLine(rest, SCon{char, reversed})

def initialRoot(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{' ', _}: True{}
    case SCon{'\t', _}: True{}
    case SCon{'\n', _}: True{}
    case _: False{}

def rooted(root: Bool, words: List<&2, String>) -> List<&2, String>:
  match root:
    case True{}: "" <> words
    case False{}: words

def domainWords(+text: String) -> List<&2, String>:
  rooted(initialRoot(text), Config.words(firstLine(text, ""), Config.Words{"", Nil{}}))

def domainOverride(value: Maybe<&2, String>) -> Maybe<&2, List<&2, String>>:
  match value:
    case None{}: None{}
    case Some{text}: Some{domainWords(text)}

def optionWords(value: Maybe<&2, String>) -> List<&2, String>:
  match value:
    case None{}: Nil{}
    case Some{text}: Config.words(text, Config.Words{"", Nil{}})

# Options remain tokens: selecting a diagnostic policy is a separate step.
def overrides(hostname: Maybe<&2, String>, values: Values) -> Settings.Overrides:
  match values:
    case Values{local, options}: Settings.Overrides{hostname, domainOverride(local), optionWords(options)}
