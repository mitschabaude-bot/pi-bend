import Base
import ./types.bend as Auth
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/filesystem.bend as FS

# Default auth context: environment variables from the process (blank values
# are unset) and file existence through the OS, with a leading `~` expanded.

def present(value: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match value:
    case Fail{_}: None{}
    case Done{+text}: Bool.pick(Maybe<&2, String>, String.is_empty(String.trim(text)), None{}, Some{text})

def envValue(unused: Unit, name: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    value : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return present(value)

def expanded(home: Result<&2, &2, FS.Error, String>, rest: String) -> Maybe<&2, String>:
  match home:
    case Fail{_}: None{}
    case Done{directory}: Some{directory ++ rest}

def accessible(result: Result<&1, &1, U32 & String, Unit>) -> Bool:
  match result:
    case Done{Unit{}}: True{}
    case Fail{_}: False{}

def accessed(path: Maybe<&2, String>) -> IO(Bool):
  match path:
    case None{}: IO.pure(Bool, False{})
    case Some{value}:
      do IO<Bool>:
        result : Result<&1, &1, U32 & String, Unit> <- File.access(value, 0)
        return accessible(result)

def fileExists(unused: Unit, path: String) -> IO(Bool):
  match path:
    case SCon{'~', rest}:
      do IO<Bool>:
        home : Result<&2, &2, FS.Error, String> <- FS.homedir()
        accessed(expanded(home, rest))
    case other: accessed(Some{other})

def defaultProviderAuthContext() -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    environment : C.Callback<String, Maybe<&2, String>> <- C.create(~Unit, ~String, ~Maybe<&2, String>, ~envValue, Unit{})
    exists : C.Callback<String, Bool> <- C.create(~Unit, ~String, ~Bool, ~fileExists, Unit{})
    return Auth.AuthContext{environment, exists}
