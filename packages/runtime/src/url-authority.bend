import Base
import ./url-percent.bend as Percent

# Tokens from an already-delimited non-file authority. Host normalization and
# port validation are separate stages. Some{empty credentials/port} preserves
# syntax needed by the enclosing parser's empty-host and scheme checks.
type Credentials is Data:
  Credentials{username: String, password: String}

type Tokens is Data:
  Tokens{credentials: Maybe<&2, Credentials>, host: String, port: Maybe<&2, String>}

type UserHost is Data:
  UserHost{credentials: Maybe<&2, Credentials>, hostPort: String}

def credentials(text: String, reversedUsername: String) -> Credentials:
  match text:
    case SNil{}: Credentials{Percent.encode(Percent.UserInfo{}, String.reverse(reversedUsername)), ""}
    case SCon{':', password}: Credentials{Percent.encode(Percent.UserInfo{}, String.reverse(reversedUsername)), Percent.encode(Percent.UserInfo{}, password)}
    case SCon{char, rest}: credentials(rest, SCon{char, reversedUsername})

# The final '@' separates userinfo from host. Earlier '@' characters belong to
# userinfo and are percent encoded there, including across the password split.
def userHost(reversed: String, hostPort: String) -> UserHost:
  match reversed:
    case SNil{}: UserHost{None{}, hostPort}
    case SCon{'@', userinfo}: UserHost{Some{credentials(String.reverse(userinfo), "")}, hostPort}
    case SCon{char, rest}: userHost(rest, SCon{char, hostPort})

def hostPort(text: String, insideBrackets: Bool, reversedHost: String, user: Maybe<&2, Credentials>) -> Tokens:
  match text insideBrackets:
    case SNil{} _: Tokens{user, String.reverse(reversedHost), None{}}
    case SCon{':', port} False{}: Tokens{user, String.reverse(reversedHost), Some{port}}
    case SCon{'[', rest} _: hostPort(rest, True{}, SCon{'[', reversedHost}, user)
    case SCon{']', rest} _: hostPort(rest, False{}, SCon{']', reversedHost}, user)
    case SCon{char, rest} brackets: hostPort(rest, brackets, SCon{char, reversedHost}, user)

def separated(input: UserHost) -> Tokens:
  match input:
    case UserHost{user, text}: hostPort(text, False{}, "", user)

def parse(input: String) -> Tokens:
  separated(userHost(String.reverse(input), ""))

type Prefix is Data:
  Prefix{tokens: Tokens, remainder: String}

def finish(reversed: String, remainder: String) -> Prefix:
  Prefix{parse(String.reverse(reversed)), remainder}

# Called after the URL parser enters the authority state. Keep the delimiter in
# the remainder so the enclosing path/query/fragment state can consume it.
def scan(text: String, special: Bool, reversed: String) -> Prefix:
  match text special:
    case SNil{} _: finish(reversed, "")
    case SCon{'/', rest} _: finish(reversed, SCon{'/', rest})
    case SCon{'?', rest} _: finish(reversed, SCon{'?', rest})
    case SCon{'#', rest} _: finish(reversed, SCon{'#', rest})
    case SCon{'\\', rest} True{}: finish(reversed, SCon{'\\', rest})
    case SCon{char, rest} isSpecial: scan(rest, isSpecial, SCon{char, reversed})

def read(text: String, special: Bool) -> Prefix:
  scan(text, special, "")
