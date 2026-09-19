import Base
import ./idna-label.bend as Label
import ./idna-prepare.bend as Prepare
import ./idna-mapping.bend as Mapping
import ./idna-domain-policy.bend as Policy
import ./idna-ace.bend as ACE
import ./punycode.bend as Punycode
import ./punycode-core.bend as Core
import ./string-split.bend as Split

type Options is Data:
  Options{label: Label.Options, checkBidi: Bool, verifyDNSLength: Bool}

type Error is Data:
  Preparation{reason: Mapping.MappingError}
  InvalidLabel{index: Nat, reason: Label.Error}
  Encoding{index: Nat, reason: Core.Error}
  BidiDomain{}
  DNSLength{}

type State is Data:
  State{index: Nat, reversed: List<&2, String>, bidi: Policy.BidiState}

def prepend(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char, rest}: prepend(rest, SCon{char, reversed})

def separator(first: Bool, reversed: String) -> String:
  match first:
    case True{}: reversed
    case False{}: SCon{'.', reversed}

def join(labels: List<&2, String>, first: Bool, reversed: String) -> String:
  match labels:
    case Nil{}: String.reverse(reversed)
    case label <> rest: join(rest, False{}, prepend(label, separator(first, reversed)))

def asciiResult(result: Result<&2, &2, Core.Error, String>) -> Result<&2, &2, Core.Error, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{text}: Done{"xn--" ++ text}

def encode(ascii: Bool, text: String) -> Result<&2, &2, Core.Error, String>:
  match ascii:
    case True{}: Done{text}
    case False{}: asciiResult(Punycode.encode(text))

def afterEncoding(result: Result<&2, &2, Core.Error, String>, label: Label.Label, state: State) -> Result<&2, &2, Error, State>:
  match result state:
    case Fail{error} State{index, _, _}: Fail{Encoding{index, error}}
    case Done{text} State{index, reversed, bidi}: Done{State{Succ{index}, text <> reversed, Policy.bidiPush(bidi, label)}}

def encodeLabel(label: Label.Label, state: State) -> Result<&2, &2, Error, State>:
  match label:
    case Label.Label{+text, empty, bidi}:
      afterEncoding(encode(ACE.isASCII(text), text), Label.Label{text, empty, bidi}, state)

def afterLabel(result: Result<&2, &2, Label.Error, Label.Label>, state: State) -> Result<&2, &2, Error, State>:
  match result state:
    case Fail{error} State{index, _, _}: Fail{InvalidLabel{index, error}}
    case Done{label} previous: encodeLabel(label, previous)

def completed(bidiValid: Bool, dnsValid: Bool, labels: List<&2, String>) -> Result<&2, &2, Error, String>:
  match bidiValid dnsValid:
    case False{} _: Fail{BidiDomain{}}
    case True{} False{}: Fail{DNSLength{}}
    case True{} True{}: Done{join(labels, True{}, "")}

def checkLength(enabled: Bool, labels: List<&2, String>) -> Bool:
  match enabled:
    case False{}: True{}
    case True{}: Policy.dnsLengthValid(labels)

def finish(state: State, checkBidi: Bool, verifyDNSLength: Bool) -> Result<&2, &2, Error, String>:
  match state:
    case State{_, +reversed, bidi}:
      completed(Bool.not(checkBidi) || Policy.bidiFinish(bidi), checkLength(verifyDNSLength, reversed), List.reverse(&2, String, reversed))

def scan(labels: List<&2, String>, +context: Label.Context, +options: Label.Options, checkBidi: Bool, verifyDNSLength: Bool, state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, String>:
  match labels state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: finish(value, checkBidi, verifyDNSLength)
    case label <> rest Done{value}: scan(rest, context, options, checkBidi, verifyDNSLength, afterLabel(Label.process(context, options, label), value))

def prepared(result: Result<&2, &2, Mapping.MappingError, String>, context: Label.Context, options: Options) -> Result<&2, &2, Error, String>:
  match result options:
    case Fail{error} _: Fail{Preparation{error}}
    case Done{text} Options{label, checkBidi, verifyDNSLength}:
      scan(Split.split(text, '.'), context, label, checkBidi, verifyDNSLength, Done{State{0n, Nil{}, Policy.bidiStart()}})

def prepare(context: Label.Context, options: Label.Options, input: String) -> Result<&2, &2, Mapping.MappingError, String>:
  match context options:
    case Label.Context{mapping, normalization, _} Label.Options{_, _, _, mode}:
      Prepare.prepare(Prepare.Context{mapping, normalization}, mode, input)

# Strict UTS #46 ToASCII with explicit flags and reusable immutable Unicode
# tables. No default URL compatibility policy is selected here. URL host parsing
# must additionally reject forbidden host characters and handle numeric hosts.
def toASCII(+context: Label.Context, options: Options, input: String) -> Result<&2, &2, Error, String>:
  match options:
    case Options{+label, +checkBidi, +verifyDNSLength}:
      prepared(prepare(context, label, input), context, Options{label, checkBidi, verifyDNSLength})
