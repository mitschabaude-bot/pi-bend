import Base
import ../src/api/openai-responses-policy.bend as P
import ../src/types.bend as T
import ../../runtime/src/record.bend as R
import ../../runtime/test/utf8-runner.bend as H

def decodeText(value: String) -> String: H.fromScalars(H.parseNumbers(value))
def optionalText(value: String) -> Maybe<&2, String>:
  match value:
    case "-": None{}
    case other: Some{decodeText(other)}

def flag(value: String) -> Maybe<&2, Bool>:
  match value:
    case "1": Some{True{}}
    case "0": Some{False{}}
    case _: None{}

def affinity(value: String) -> Maybe<&2, T.SessionAffinityFormat>:
  match value:
    case "a": Some{T.OpenAISession{}}
    case "n": Some{T.OpenAINoSession{}}
    case "r": Some{T.OpenRouterSession{}}
    case _: None{}

def compat(values: List<&2, String>) -> Maybe<&2, T.OpenAIResponsesCompat>:
  match values:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> Nil{}: Some{T.OpenAIResponsesCompat{flag(a), flag(b), affinity(c), flag(d), flag(e), flag(f), flag(g), flag(h), flag(i), flag(j)}}
    case _: None{}

def retention(value: String) -> Maybe<&2, T.CacheRetention>:
  match value:
    case "none": Some{T.CacheNone{}}
    case "short": Some{T.CacheShort{}}
    case "long": Some{T.CacheLong{}}
    case _: None{}

def showBool(value: Bool) -> String: Bool.pick(String, value, "1", "0")
def showAffinity(value: T.SessionAffinityFormat) -> String:
  match value:
    case T.OpenAISession{}: "a"
    case T.OpenAINoSession{}: "n"
    case T.OpenRouterSession{}: "r"

def showCompat(value: P.ResolvedCompat) -> String:
  match value:
    case P.ResolvedCompat{a, b, c, d, e, f, g, h, i, j}: String.join(showBool(a) <> showBool(b) <> showAffinity(c) <> showBool(d) <> showBool(e) <> showBool(f) <> showBool(g) <> showBool(h) <> showBool(i) <> showBool(j) <> Nil{}, ".")

def showRetention(value: T.CacheRetention) -> String:
  match value:
    case T.CacheNone{}: "none"
    case T.CacheShort{}: "short"
    case T.CacheLong{}: "long"

def showText(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: H.showText(text)

def showOptions(value: Maybe<&2, P.PromptCacheOptions>) -> String:
  match value:
    case None{}: "-"
    case Some{P.ExplicitMode{}}: "explicit"
    case Some{P.ThirtyMinuteTtl{}}: "30m"

def headers(value: P.ResolvedCompat, session: Maybe<&2, String>) -> String:
  match value:
    case P.ResolvedCompat{_, _, format, _, _, _, _, _, _, _}:
      +fields = P.affinityHeaders(format, session)
      String.join(showText(R.get(String, fields, "session_id")) <> showText(R.get(String, fields, "x-client-request-id")) <> showText(R.get(String, fields, "x-session-id")) <> Nil{}, "|")

def projection(+value: P.ResolvedCompat, +retained: T.CacheRetention, +session: Maybe<&2, String>) -> String:
  String.join(showCompat(value) <> showRetention(retained) <> showText(P.getPromptCacheRetention(value, retained)) <> showOptions(P.getPromptCacheOptions(value, retained)) <> showText(P.cacheSessionId(retained, session)) <> showText(P.promptCacheKey(retained, session)) <> headers(value, P.cacheSessionId(retained, session)) <> Nil{}, "|")

def assertEqual(actual: String, expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "Responses policy mismatch"))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case provider <> url <> flags <> cache <> env <> session <> expected <> Nil{}: assertEqual(projection(P.getCompat(decodeText(provider), decodeText(url), compat(String.split(flags, '.'))), P.resolveCacheRetentionValue(retention(cache), optionalText(env)), optionalText(session)), expected)
    case _: IO.die(Unit, 1, "invalid policy fixture")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS Responses policy")
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, ';'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
