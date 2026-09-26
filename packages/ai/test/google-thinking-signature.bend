import Base
import ../src/api/google-shared.bend as Shared
import ./anthropic-harness.bend as A

# pi-mono f07218c4d packages/ai/test/google-thinking-signature.test.ts.
def run() -> IO(Unit):
  do IO<Unit>:
    A.check(Shared.isThinkingPart(Some{True{}}) && Shared.isThinkingPart(Some{True{}}), "thought true")
    A.pass("treats part.thought === true as thinking")
    A.check(Bool.not(Shared.isThinkingPart(None{})) && Bool.not(Shared.isThinkingPart(Some{False{}})), "signature alone")
    A.pass("does not treat thoughtSignature alone as thinking")
    A.check(Bool.not(Shared.isThinkingPart(None{})) && Bool.not(Shared.isThinkingPart(Some{False{}})), "missing signatures")
    A.pass("does not treat empty/missing signatures as thinking if thought is not set")
    +first : Maybe<&2, String> <- IO.pure(Maybe<&2, String>, Shared.retainThoughtSignature(None{}, Some{"sig-1"}))
    A.equalText(first, Some{"sig-1"}, "first")
    +second : Maybe<&2, String> <- IO.pure(Maybe<&2, String>, Shared.retainThoughtSignature(first, None{}))
    A.equalText(second, Some{"sig-1"}, "second")
    A.equalText(Shared.retainThoughtSignature(second, Some{""}), Some{"sig-1"}, "third")
    A.pass("preserves the existing signature when subsequent deltas omit thoughtSignature")
    A.equalText(Shared.retainThoughtSignature(Some{"sig-1"}, Some{"sig-2"}), Some{"sig-2"}, "updated")
    A.pass("updates the signature when a new non-empty signature arrives")
