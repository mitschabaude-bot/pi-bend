import Base
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/fetch.bend as Fetch

# pi-mono f07218c4d packages/ai/test/fetch-option.test.ts, the Anthropic case:
# streamSimple passes options.fetch to the SDK request, and the process fetch
# (globalThis.fetch) is not called.
def called(value: Maybe<&2, Fetch.Input<Unit>>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def checked(+name: String, outcome: H.FetchOutcome) -> IO(Unit):
  match outcome:
    case H.FetchOutcome{ambient, custom}:
      do IO<Unit>:
        H.check(called(custom), name ++ ": the custom fetch was not called")
        H.check(Bool.not(called(ambient)), name ++ ": the ambient fetch was called")
        H.pass(name)

def run() -> IO(Unit):
  +model = H.custom("test-model", "Test Model", "test-provider", "https://upstream.test/v1", 1000, 10000, None{}, None{})
  do IO<Unit>:
    outcome : H.FetchOutcome <- H.fetchRun(model, H.hello())
    checked("passes fetch through streamSimple to the Anthropic SDK", outcome)
