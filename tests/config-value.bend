import Base
import ../packages/coding-agent/src/core/resolve-config-value.bend as ConfigValue
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/types.bend as Ai

# Fixture for resolve-config-value: `resolve <config> [NAME=value ...]`
# resolves once with the given credential-scoped env; `twice <config>`
# resolves the same value twice through one resolver (the command cache);
# `uncached <config>` resolves twice without caching; `names <config>` lists
# the referenced environment variable names; `command <config>` reports
# whether the value is a shell command.

def show(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "some:" ++ text

def split(entry: String, reversed: String) -> R.Property<String>:
  match entry:
    case SNil{}: R.Property{String.reverse(reversed), ""}
    case SCon{'=', rest}: R.Property{String.reverse(reversed), rest}
    case SCon{c, rest}: split(rest, SCon{c, reversed})

def properties(entries: List<String>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: split(entry, "") <> properties(rest)

def scope(entries: List<String>) -> Maybe<&2, Ai.ProviderEnv()>:
  match entries:
    case Nil{}: None{}
    case values: Some{R.Record{properties(values)}}

def resolveOnce(config: String, env: List<String>) -> IO(Unit):
  do IO<Unit>:
    +resolver : ConfigValue.Resolver <- ConfigValue.newResolver()
    value : Maybe<&2, String> <- ConfigValue.resolveConfigValue(resolver, config, scope(env))
    ConfigValue.disposeResolver(resolver)
    IO.print(show(value))

def resolveTwice(+config: String) -> IO(Unit):
  do IO<Unit>:
    +resolver : ConfigValue.Resolver <- ConfigValue.newResolver()
    first : Maybe<&2, String> <- ConfigValue.resolveConfigValue(resolver, config, None{})
    second : Maybe<&2, String> <- ConfigValue.resolveConfigValue(resolver, config, None{})
    ConfigValue.clearConfigValueCache(resolver)
    third : Maybe<&2, String> <- ConfigValue.resolveConfigValue(resolver, config, None{})
    ConfigValue.disposeResolver(resolver)
    IO.print(show(first) ++ "|" ++ show(second) ++ "|" ++ show(third))

def resolveUncached(+config: String) -> IO(Unit):
  do IO<Unit>:
    first : Maybe<&2, String> <- ConfigValue.resolveConfigValueUncached(config, None{})
    second : Maybe<&2, String> <- ConfigValue.resolveConfigValueUncached(config, None{})
    IO.print(show(first) ++ "|" ++ show(second))

def run(values: List<String>) -> IO(Unit):
  match values:
    case "resolve" <> config <> env: resolveOnce(config, env)
    case "twice" <> config <> Nil{}: resolveTwice(config)
    case "uncached" <> config <> Nil{}: resolveUncached(config)
    case "names" <> config <> Nil{}: IO.print(String.join(ConfigValue.getConfigValueEnvVarNames(config), ","))
    case "name" <> config <> Nil{}: IO.print(show(ConfigValue.getConfigValueEnvVarName(config)))
    case "command" <> config <> Nil{}: IO.print(Bool.show(ConfigValue.isCommandConfigValue(config)))
    case _: IO.die(Unit, 2, "usage: resolve|twice|uncached|names|name|command <config> [NAME=value ...]")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
