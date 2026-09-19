import Base
import ../src/utils/provider-env.bend as Env
import ../src/api/openai-responses-policy.bend as Policy
import ../src/types.bend as T
import ../../runtime/src/record.bend as R
import ../../runtime/test/utf8-runner.bend as H
import ./openai-responses-policy-runner.bend as P

def environment(value: String) -> Maybe<&2, T.ProviderEnv()>:
  match value:
    case "-": None{}
    case other: Some{R.Record{R.Property{"PI_CACHE_RETENTION", H.fromScalars(H.parseNumbers(other))} <> Nil{}}}

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case +override <> explicit <> expected <> Nil{}:
      do IO<Unit>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", environment(override))
        retained : T.CacheRetention <- Policy.resolveCacheRetention(P.retention(explicit), environment(override))
        P.assertEqual(P.showText(value) ++ "|" ++ P.showRetention(retained), expected)
    case _: IO.die(Unit, 1, "invalid environment fixture")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
