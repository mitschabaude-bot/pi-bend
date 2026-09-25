import Base

# Reproducer for docs/bend-issues.md BEND-046: grow a text to 10 KB by 500
# deltas of 20 characters, as a streamed answer does. `shared MODE` appends to
# the version a consumer retains; `private MODE` appends to a unique
# accumulator and hands the consumer a copy. MODE `none` retains no version,
# `last` the latest, `keep` every one. Time each run natively:
#   sh scripts/build-pure.sh tests/string-append-retained.bend build/string-append-retained
#   /usr/bin/time -f '%e s %M KB' build/string-append-retained shared last
def delta(+i: Nat) -> String: String.take("abcdefghijklmnopqrstuvwxyz" ++ Nat.show(i) ++ "0123456789", 20n)

def keep(+mode: Nat, s: String, kept: List<&2, String>) -> List<&2, String>:
  match mode:
    case 0n: Nil{}
    case 1n: s <> Nil{}
    case _: s <> kept

def mode(m: String) -> Nat:
  match m:
    case "keep": 2n
    case "last": 1n
    case _: 0n

def paired(+h: Char, p: String & String) -> String & String:
  match p:
    case (a, b): (SCon{h, a}, SCon{h, b})
def copy2(s: String) -> String & String:
  match s:
    case SNil{}: ("", "")
    case SCon{+h, t}: paired(h, copy2(t))
def shared(+mode: Nat, n: Nat, +acc: String, kept: List<&2, String>) -> Nat:
  match n:
    case 0n: String.length(acc) + List.length(&2, String, kept)
    case 1n+ +k:
      +next = acc ++ delta(k)
      shared(mode, k, next, keep(mode, next, kept))
def private(+mode: Nat, n: Nat, pair: String & String, kept: List<&2, String>) -> Nat:
  match n pair:
    case 0n Tuple{acc, _}: String.length(acc) + List.length(&2, String, kept)
    case 1n+ +k Tuple{acc, snapshot}: private(mode, k, copy2(acc ++ delta(k)), keep(mode, snapshot, kept))
def run(args: List<String>) -> Nat:
  match args:
    case "shared" <> m <> _: shared(mode(m), 500n, "", Nil{})
    case "private" <> m <> _: private(mode(m), 500n, ("", ""), Nil{})
    case _: 0n
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    IO.print(Nat.show(run(args)))