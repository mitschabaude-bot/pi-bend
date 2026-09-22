import Base
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/u64.bend as W

# Peer evidence cannot create trust, regardless of its contents or graph shape.
# This covers self-signed roots, chains and cycles supplied by an untrusted peer.
law no_configured_anchor:
  for steps: Nat
  for now: W.U64
  for leaf: X509.Certificate
  for peers: List<&2,X509.Certificate>
  {X509.verifyChain(steps,now,leaf,peers,Nil{}) == Fail{X509.NoTrustedPath{}} : Result<&2,&2,X509.Error,X509.PublicKey>}
