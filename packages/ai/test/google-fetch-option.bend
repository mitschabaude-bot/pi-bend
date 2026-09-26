import Base
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H
import ../../runtime/src/fetch.bend as Fetch

# pi-mono f07218c4d packages/ai/test/fetch-option.test.ts, the Google
# Generative AI cases (the Vertex half of the rejection test waits for the
# Vertex adapter). The setup's process fetch stands for globalThis.fetch.
def model() -> T.Model<T.JsonValue>:
  H.model(T.GoogleGenerativeAiApi{}, "test-model", "Test Model", "test-provider", "https://upstream.test/v1", False{}, 1000, 10000, None{})

def called(value: Maybe<&2, Fetch.Input<Unit>>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def rejected(+name: String, outcome: H.FetchOutcome) -> IO(Unit):
  match outcome:
    case H.FetchOutcome{+message, ambient, custom}:
      do IO<Unit>:
        A.check(A.contains(H.errorMessage(message), "Custom fetch is not supported by the Google Generative AI adapter"), name ++ ": " ++ A.showMaybe(H.errorMessage(message)))
        A.check(Bool.not(called(custom)), name ++ ": the custom fetch was called")
        A.check(Bool.not(called(ambient)), name ++ ": the ambient fetch was called")
        A.pass(name)

def allowed(+name: String, outcome: H.FetchOutcome) -> IO(Unit):
  match outcome:
    case H.FetchOutcome{+message, ambient, _}:
      do IO<Unit>:
        A.check(called(ambient), name ++ ": the ambient fetch was not called")
        A.check(Bool.not(A.contains(H.errorMessage(message), "Custom fetch is not supported")), name ++ ": " ++ A.showMaybe(H.errorMessage(message)))
        A.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    custom : H.FetchOutcome <- H.fetchRun(model(), H.hello(), False{})
    rejected("rejects custom fetch for Google adapters instead of silently bypassing it", custom)
    ambient : H.FetchOutcome <- H.fetchRun(model(), H.hello(), True{})
    allowed("allows Google adapters to receive globalThis.fetch explicitly", ambient)
