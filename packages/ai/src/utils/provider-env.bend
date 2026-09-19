import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R

# Scoped nonempty values take precedence. Empty values fall back to the process
# environment; whitespace is a value, not an instruction to remove the key.
def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SNil{}}: None{}
    case other: other

def scoped(name: String, env: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, String>:
  match env:
    case None{}: None{}
    case Some{fields}: nonempty(R.get(String, fields, name))

# Bend's native getenv accesses the actual environment. The TypeScript Bun
# compiled-binary /proc fallback is not needed by this backend.
def processValue(value: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match value:
    case Done{text}: nonempty(Some{text})
    case Fail{_}: None{}

def resolve(name: String, value: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match value:
    case Some{text}: IO.pure(Maybe<&2, String>, Some{text})
    case None{}:
      do IO<Maybe<&2, String>>:
        result : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
        return processValue(result)

def getProviderEnvValue(+name: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, String>):
  resolve(name, scoped(name, env))
