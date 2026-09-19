import Base
import ./idna-label.bend as Label
import ./idna-bidi.bend as Bidi

type BidiState is Data:
  BidiState{hasRTL: Bool, labelsValid: Bool}

def bidiStart() -> BidiState:
  BidiState{False{}, True{}}

def bidiPush(state: BidiState, label: Label.Label) -> BidiState:
  match state label:
    case BidiState{rtl, valid} Label.Label{_, empty, Bidi.Analysis{labelRTL, labelValid}}:
      BidiState{rtl || labelRTL, valid && (empty || labelValid)}

def bidiFinish(state: BidiState) -> Bool:
  match state:
    case BidiState{rtl, valid}: Bool.not(rtl) || valid

def bidiScan(labels: List<&2, Label.Label>, state: BidiState) -> Bool:
  match labels:
    case Nil{}: bidiFinish(state)
    case label <> rest: bidiScan(rest, bidiPush(state, label))

# Every nonempty label participates, regardless of where RTL was encountered.
def bidiValid(labels: List<&2, Label.Label>) -> Bool:
  bidiScan(labels, bidiStart())

type Length is Data:
  Length{size: U32, ascii: Bool}

type DNSState is Data:
  DNSState{used: U32, valid: Bool}

# Saturate above all relevant bounds so arbitrary input lengths cannot wrap.
def bounded(value: U32, exceeds: Bool) -> U32:
  match exceeds:
    case True{}: 255
    case False{}: value

def add(+left: U32, +right: U32) -> U32:
  bounded((left + right : U32), U32.is_gt((left + right : U32), 255))

def lengthScan(text: String, size: U32, ascii: Bool) -> Length:
  match text:
    case SNil{}: Length{size, ascii}
    case SCon{Chr{code}, rest}: lengthScan(rest, add(size, 1), ascii && U32.is_le(code, 127))

def dnsPush(state: DNSState, value: Length) -> DNSState:
  match state value:
    case DNSState{used, valid} Length{+size, ascii}:
      DNSState{add(used, add(size, 1)), valid && ascii && U32.is_gt(size, 0) && U32.is_le(size, 63)}

def dnsFinish(state: DNSState) -> Bool:
  match state:
    case DNSState{+used, valid}: valid && U32.is_gt(used, 0) && U32.is_le(used, 254)

def dnsScan(labels: List<&2, String>, state: DNSState) -> Bool:
  match labels:
    case Nil{}: dnsFinish(state)
    case label <> rest: dnsScan(rest, dnsPush(state, lengthScan(label, 0, True{})))

# Input is a list of already-ASCII labels, after Punycode conversion. A final
# empty root label also fails when UTS #46 VerifyDnsLength is enabled. used
# includes one separator per label, hence the 254 bound represents at most
# 253 ASCII characters. URL hosts can disable this entire strict length check.
def dnsLengthValid(labels: List<&2, String>) -> Bool:
  dnsScan(labels, DNSState{0, True{}})
