import Base
import ../../src/api/openai-text-signature.bend as S
import ../../src/types.bend as T
import ../../../runtime/src/utf16.bend as U
import ../../../runtime/test/schema.bend as A

def samePhase(left: Maybe<&2,T.TextSignaturePhase>, right: Maybe<&2,T.TextSignaturePhase>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{T.Commentary{}} Some{T.Commentary{}}: True{}
    case Some{T.FinalAnswer{}} Some{T.FinalAnswer{}}: True{}
    case _ _: False{}

def same(left: Maybe<&2,T.TextSignatureV1>, right: Maybe<&2,T.TextSignatureV1>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{T.TextSignatureV1{a,p}} Some{T.TextSignatureV1{b,q}}: U.equal(a,b) && samePhase(p,q)
    case _ _: False{}

def decode(input: Maybe<&2,String>, expected: Maybe<&2,T.TextSignatureV1>, label: String) -> IO(Unit):
  A.assertion(same(S.parseTextSignature(input),expected),label)

def encode(+id: String, +phase: Maybe<&2,T.TextSignaturePhase>, expected: String, label: String) -> IO(Unit):
  +actual = S.encodeTextSignatureV1(id,phase)
  A.assertion(U.equal(actual,expected) && same(S.parseTextSignature(Some{actual}),Some{T.TextSignatureV1{id,phase}}),label)
